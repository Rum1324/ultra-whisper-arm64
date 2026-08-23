#!/usr/bin/env python3
"""
Tests for `summarize.chunker`.

The properties that matter here are structural rather than cosmetic — nothing
downstream can recover from a lost segment or a window that quietly blew the
context — so the multi-window cases assert over a generated transcript rather
than over two hand-written segments.
"""

import random

import pytest

from summarize.chunker import (
    DEFAULT_OVERLAP_RATIO,
    DEFAULT_WINDOW_BUDGET_CHARS,
    MAX_OVERLAP_RATIO,
    _segment_cost,
    chunk_transcript,
)
from summarize.contracts import Segment

# Sentences long enough that a handful of them cross a small test budget, and
# varied enough that segment costs are not all identical.
_LINES = [
    "I think we should ship the rolling transcribe path before the summarizer.",
    "Right, that lines up with what the capture layer needs anyway.",
    "One catch: whisper restarts its timestamps every call.",
    "We add the window offset before we build the segment, so that is handled.",
    "Can you take the Ollama side and I take the chunker?",
    "Sure. I will have something by Friday, probably Thursday.",
    "Let us keep the map prompt small so the two-gig model still fits it.",
    "Agreed, and we fall back to a bigger tag if the note comes out thin.",
]


def _seg(t0: float, t1: float, speaker: str, text: str) -> Segment:
    return Segment(t0=t0, t1=t1, speaker=speaker, text=text)


def _meeting(count: int, *, seed: int = 7, speakers=("me", "them")) -> list:
    """A plausible time-ordered two-track transcript of `count` segments."""
    rng = random.Random(seed)
    segments = []
    clock = 0.0
    for i in range(count):
        duration = rng.uniform(1.5, 6.0)
        text = _LINES[i % len(_LINES)]
        if rng.random() < 0.3:
            text = text + " " + _LINES[(i + 3) % len(_LINES)]
        segments.append(
            _seg(clock, clock + duration, speakers[i % len(speakers)], text)
        )
        clock += duration + rng.uniform(0.0, 1.2)
    return segments


def _window_cost(window) -> int:
    return sum(_segment_cost(s) for s in window.segments)


# ---------------------------------------------------------------------------
# Degenerate inputs
# ---------------------------------------------------------------------------


def test_empty_transcript_yields_no_windows():
    assert chunk_transcript([]) == []


def test_all_blank_segments_yield_no_windows():
    segments = [
        _seg(0.0, 1.0, "me", ""),
        _seg(1.0, 2.0, "them", "   "),
        _seg(2.0, 3.0, "me", "\n\t "),
    ]
    assert chunk_transcript(segments) == []


def test_single_segment_is_one_window():
    segment = _seg(3.5, 9.25, "them", "Just the one thing, then.")
    windows = chunk_transcript([segment])

    assert len(windows) == 1
    assert windows[0].index == 0
    assert windows[0].segments == (segment,)
    assert windows[0].t0 == 3.5
    assert windows[0].t1 == 9.25


def test_oversized_single_segment_is_emitted_whole():
    """A segment past the budget must still reach the model, uncut."""
    text = "word " * 4000
    segment = _seg(0.0, 600.0, "me", text)

    windows = chunk_transcript([segment], budget_chars=200)

    assert len(windows) == 1
    assert windows[0].segments == (segment,)
    assert windows[0].segments[0].text == text
    assert _window_cost(windows[0]) > 200


def test_every_segment_oversized_still_terminates_one_per_window():
    segments = [_seg(float(i) * 10, float(i) * 10 + 9, "me", "x" * 500) for i in range(5)]

    windows = chunk_transcript(segments, budget_chars=100)

    assert len(windows) == 5
    assert [w.segments[0] for w in windows] == segments
    assert all(len(w.segments) == 1 for w in windows)


def test_short_transcript_is_a_single_window_without_overlap():
    segments = _meeting(6)
    assert sum(_segment_cost(s) for s in segments) < DEFAULT_WINDOW_BUDGET_CHARS

    windows = chunk_transcript(segments)

    assert len(windows) == 1
    assert windows[0].segments == tuple(segments)


# ---------------------------------------------------------------------------
# Content handling
# ---------------------------------------------------------------------------


def test_blank_segments_are_dropped_but_neighbours_survive():
    kept_first = _seg(0.0, 2.0, "me", "Real content here.")
    kept_last = _seg(6.0, 8.0, "them", "And the reply.")
    segments = [
        kept_first,
        _seg(2.0, 4.0, "them", "   "),
        _seg(4.0, 6.0, "me", ""),
        kept_last,
    ]

    windows = chunk_transcript(segments)

    assert len(windows) == 1
    assert windows[0].segments == (kept_first, kept_last)
    assert windows[0].t0 == 0.0
    assert windows[0].t1 == 8.0


def test_zero_duration_segments_are_kept():
    """whisper does emit t0 == t1; they are speech, not padding."""
    segments = [
        _seg(0.0, 0.0, "me", "Yeah."),
        _seg(1.0, 1.0, "them", "Mm."),
        _seg(2.0, 4.0, "me", "Anyway, about the schedule."),
    ]

    windows = chunk_transcript(segments)

    assert len(windows) == 1
    assert windows[0].segments == tuple(segments)
    assert windows[0].t0 == 0.0
    assert windows[0].t1 == 4.0


def test_speakers_interleave_within_a_window():
    segments = _meeting(40)

    windows = chunk_transcript(segments, budget_chars=1200)

    assert len(windows) > 1
    for window in windows:
        speakers = [s.speaker for s in window.segments]
        # Chronological order preserved, so the tracks alternate rather than
        # arriving as one block of "me" followed by one block of "them".
        assert set(speakers) == {"me", "them"}
        assert [s.t0 for s in window.segments] == sorted(s.t0 for s in window.segments)


def test_single_speaker_transcript_chunks_normally():
    segments = _meeting(40, speakers=("me",))

    windows = chunk_transcript(segments, budget_chars=1200)

    assert len(windows) > 1
    assert all(s.speaker == "me" for w in windows for s in w.segments)
    assert {s.text for w in windows for s in w.segments} == {s.text for s in segments}


def test_out_of_order_input_is_re_sorted():
    early = _seg(0.0, 2.0, "me", "First thing said.")
    late = _seg(10.0, 12.0, "them", "Later thing said.")

    windows = chunk_transcript([late, early])

    assert windows[0].segments == (early, late)
    assert windows[0].t0 == 0.0


def test_window_t1_accounts_for_a_segment_that_outlasts_a_later_one():
    long_one = _seg(0.0, 30.0, "them", "A long uninterrupted stretch of talking.")
    short_one = _seg(5.0, 7.0, "me", "Mhm.")

    windows = chunk_transcript([long_one, short_one])

    assert windows[0].t1 == 30.0


# ---------------------------------------------------------------------------
# Multi-window structural properties
# ---------------------------------------------------------------------------


def test_long_meeting_holds_order_indices_coverage_and_overlap():
    segments = _meeting(400)
    budget = 1500

    windows = chunk_transcript(segments, budget_chars=budget)

    assert len(windows) > 5, "test transcript should be long enough to be interesting"

    # Indices sequential from zero.
    assert [w.index for w in windows] == list(range(len(windows)))

    # Time order, non-decreasing t0, and coherent bounds.
    assert [w.t0 for w in windows] == sorted(w.t0 for w in windows)
    for window in windows:
        assert window.segments, "no window may be empty"
        assert window.t0 == min(s.t0 for s in window.segments)
        assert window.t1 == max(s.t1 for s in window.segments)
        assert window.t0 <= window.t1

    # No segment lost. Identity, not equality, so a rebuilt-or-truncated
    # segment would fail here too.
    seen = {id(s) for w in windows for s in w.segments}
    assert seen == {id(s) for s in segments}

    # Overlap actually exists between every adjacent pair, and is not
    # exorbitant: ~10% of the earlier window, plus at most one whole segment of
    # rounding.
    for earlier, later in zip(windows, windows[1:]):
        shared = [s for s in earlier.segments if id(s) in {id(x) for x in later.segments}]
        assert shared, f"windows {earlier.index}/{later.index} share no segment"
        # The shared run is a suffix of the earlier window and a prefix of the next.
        assert earlier.segments[-len(shared):] == tuple(shared)
        assert later.segments[: len(shared)] == tuple(shared)

        shared_cost = sum(_segment_cost(s) for s in shared)
        assert shared_cost >= _window_cost(earlier) * DEFAULT_OVERLAP_RATIO
        assert shared_cost <= _window_cost(earlier) * DEFAULT_OVERLAP_RATIO + max(
            _segment_cost(s) for s in shared
        )

    # Every window that holds more than one segment stayed inside the budget.
    for window in windows:
        if len(window.segments) > 1:
            assert _window_cost(window) <= budget


def test_overlap_never_repeats_more_than_half_a_budget():
    """
    A fat trailing segment must not be dragged in as "10% overlap".

    Repeating it would leave the next window a fraction of its budget for new
    material, which is worse than losing the boundary context.
    """
    budget = 400
    filler = [_seg(float(i), float(i) + 0.5, "me", "y" * 60) for i in range(4)]
    hog = _seg(10.0, 20.0, "them", "z" * 300)
    tail = [_seg(30.0 + i, 30.5 + i, "me", "w" * 60) for i in range(6)]

    windows = chunk_transcript(filler + [hog] + tail, budget_chars=budget)

    for earlier, later in zip(windows, windows[1:]):
        later_ids = {id(s) for s in later.segments}
        shared_cost = sum(_segment_cost(s) for s in earlier.segments if id(s) in later_ids)
        assert shared_cost <= budget * MAX_OVERLAP_RATIO

    # And nothing was lost to the trimming.
    assert {id(s) for w in windows for s in w.segments} == {
        id(s) for s in filler + [hog] + tail
    }


def test_windows_cover_the_transcript_contiguously():
    """Union of windows, in order, replays the whole transcript with no gaps."""
    segments = _meeting(200)

    windows = chunk_transcript(segments, budget_chars=1500)

    replay = []
    seen = set()
    for window in windows:
        for segment in window.segments:
            if id(segment) not in seen:
                seen.add(id(segment))
                replay.append(segment)
    assert [id(s) for s in replay] == [id(s) for s in segments]


def test_zero_overlap_partitions_the_transcript():
    segments = _meeting(200)

    windows = chunk_transcript(segments, budget_chars=1500, overlap_ratio=0.0)

    flat = [s for w in windows for s in w.segments]
    assert [id(s) for s in flat] == [id(s) for s in segments]


def test_smaller_budget_produces_more_windows():
    segments = _meeting(200)

    coarse = chunk_transcript(segments, budget_chars=3000)
    fine = chunk_transcript(segments, budget_chars=1000)

    assert len(fine) > len(coarse) > 1


def test_overlap_ratio_scales_the_repeated_text():
    segments = _meeting(200)

    lean = chunk_transcript(segments, budget_chars=1500, overlap_ratio=0.05)
    fat = chunk_transcript(segments, budget_chars=1500, overlap_ratio=0.3)

    assert len(fat) > len(lean)


# ---------------------------------------------------------------------------
# Parameter validation
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("budget", [0, -1, -6000])
def test_non_positive_budget_is_rejected(budget):
    with pytest.raises(ValueError):
        chunk_transcript(_meeting(3), budget_chars=budget)


@pytest.mark.parametrize("ratio", [-0.01, MAX_OVERLAP_RATIO, 0.9, 1.0])
def test_out_of_range_overlap_ratio_is_rejected(ratio):
    with pytest.raises(ValueError):
        chunk_transcript(_meeting(3), overlap_ratio=ratio)


def test_segment_cost_counts_the_rendered_prefix_not_just_the_text():
    segment = _seg(3661.0, 3663.0, "them", "Hello.")
    assert _segment_cost(segment) == len("[01:01:01] Them: Hello.") + 1
