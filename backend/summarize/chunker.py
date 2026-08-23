#!/usr/bin/env python3
"""
Cut a whole-meeting transcript into overlapping windows for the map pass.

The map pass reads one window at a time and extracts facts from it, so the
windows are the unit that has to fit in the local model's context. Everything
here exists to make that fit predictable without pulling in a tokenizer: the
backend's dependency budget is `websockets` + `numpy`, and a tokenizer would
also have to match whichever Ollama model the user picked at runtime, which is
not knowable from here.
"""

from typing import List, Sequence

from .contracts import Segment, TranscriptWindow, render_segment

# Budget for one window, in CHARACTERS OF RENDERED PROMPT TEXT — not tokens.
# There is no tokenizer here and adding one is out of scope (see module
# docstring), so this is an approximation with a known bias.
#
# Sizing: at the usual ~4 chars/token for English prose, 6000 chars is roughly
# 1500 tokens of transcript. That leaves the system prompt, FACTS_JSON_SCHEMA
# and the emitted facts JSON comfortable room inside a 4k-token context, which
# is the floor for the small local models this feature targets (the protocol's
# example tag is gemma4:e2b). It is also about 6-7 minutes of speech at a normal
# 150 wpm, so a window tends to hold one topic rather than a fragment of one.
#
# Known bias: Japanese and other CJK text runs closer to ~1 token per character,
# so a 6000-char window of Japanese can be several times its English token cost.
# The default is therefore conservative for English and NOT safe for CJK at a
# small context size — pass a smaller `budget_chars` when the meeting language
# is known to be Japanese.
DEFAULT_WINDOW_BUDGET_CHARS: int = 6000

# Fraction of a window repeated at the start of the next one. A fact stated
# across a boundary ("...so we'll ship it" / "Friday") is otherwise mangled by
# both windows, but overlap is paid for twice in tokens and once in duplicate
# facts the reduce pass has to merge, so it stays deliberately mean.
DEFAULT_OVERLAP_RATIO: float = 0.10

# Hard ceiling on repetition, used twice: a requested ratio at or above it is a
# programming error (past this the windows stop being a sliding view and become
# a rewrite of the transcript at 2x length), and no actual overlap may exceed
# this share of the budget however the rounding falls.
MAX_OVERLAP_RATIO: float = 0.5

# render_window joins segments with newlines; count that so the budget matches
# the string the model is actually handed.
_SEGMENT_SEPARATOR_CHARS: int = len("\n")


def _segment_cost(segment: Segment) -> int:
    """
    Prompt cost of one segment, measured on its rendered form.

    Counted through `render_segment` rather than `len(segment.text)` so the
    fixed `[HH:MM:SS] Them: ` prefix is included. That prefix is 17 characters
    on every line; over a 200-line window it is ~3400 characters of budget that
    a naive text-length count would silently overspend.
    """
    return len(render_segment(segment)) + _SEGMENT_SEPARATOR_CHARS


def _is_blank(segment: Segment) -> bool:
    return not segment.text.strip()


def chunk_transcript(
    segments: Sequence[Segment],
    *,
    budget_chars: int = DEFAULT_WINDOW_BUDGET_CHARS,
    overlap_ratio: float = DEFAULT_OVERLAP_RATIO,
) -> List[TranscriptWindow]:
    """
    Group a whole meeting's segments into overlapping `TranscriptWindow`s.

    `budget_chars` is a CHARACTER count of rendered prompt text, not a token
    count; see `DEFAULT_WINDOW_BUDGET_CHARS` for what that approximation is
    worth and where it breaks down.

    Behaviour worth knowing before you rely on it:

    * Windows split only on segment boundaries. A segment is one atomic run of
      speech, and half of one reads to the model as a non-sequitur, so a
      segment that alone exceeds the budget is emitted as an over-budget
      one-segment window rather than being cut or dropped.
    * Adjacent windows overlap by about `overlap_ratio` of the earlier
      window, rounded up to a whole segment. Overlap is skipped for a window
      that holds a single segment (repeating it would leave the next window no
      new ground and the walk would never advance), and trimmed or skipped
      when the rounding would repeat more than `MAX_OVERLAP_RATIO` of the
      budget. So overlap is guaranteed *typical*, not universal: assert on it
      across many boundaries, not on any one boundary.
    * Speakers interleave. Segments are kept in time order and never grouped by
      speaker — the back-and-forth is what lets the model attribute a fact to
      whoever actually said it.
    * Blank and whitespace-only segments are dropped. whisper emits them, they
      carry nothing to extract, and left in they would eat overlap slots and
      budget with empty prompt lines. A transcript of nothing but blanks
      therefore yields no windows, same as an empty one.
    * Input is stably re-sorted by `t0`. Segments are already supposed to be
      time-ordered when they arrive (see `Segment` — the rolling-transcribe
      path makes them absolute and merges the two tracks by `t0`), so for a
      well-behaved caller this is a no-op; it is here so the ordering and
      monotonic-`t0` guarantees below hold unconditionally rather than only
      when upstream is correct.

    Returns windows with sequential `index` from 0 and non-decreasing `t0`.
    Each window's `t0`/`t1` are the min/max absolute bounds of the segments it
    contains; `t1` is taken as a max rather than "last segment's t1" because
    the two-track merge orders by `t0`, and a long segment on one track can end
    after a later-starting one on the other.
    """
    if budget_chars <= 0:
        raise ValueError(f"budget_chars must be positive, got {budget_chars}")
    if not 0.0 <= overlap_ratio < MAX_OVERLAP_RATIO:
        raise ValueError(
            f"overlap_ratio must be in [0, {MAX_OVERLAP_RATIO}), got {overlap_ratio}"
        )

    ordered = sorted(
        (s for s in segments if not _is_blank(s)),
        key=lambda s: s.t0,
    )
    if not ordered:
        return []

    costs = [_segment_cost(s) for s in ordered]
    total = len(ordered)

    windows: List[TranscriptWindow] = []
    start = 0
    while start < total:
        end = _pack(costs, start, total, budget_chars)
        windows.append(_build_window(len(windows), ordered[start:end]))
        if end >= total:
            break
        start = _next_start(
            costs,
            start,
            end,
            overlap_ratio=overlap_ratio,
            budget_chars=budget_chars,
        )

    return windows


def _pack(costs: Sequence[int], start: int, total: int, budget_chars: int) -> int:
    """
    Exclusive end index of the largest run from `start` that fits the budget.

    Always advances by at least one segment, so an oversized segment produces
    an over-budget window instead of an empty one or an infinite loop.
    """
    end = start + 1
    spent = costs[start]
    while end < total and spent + costs[end] <= budget_chars:
        spent += costs[end]
        end += 1
    return end


def _next_start(
    costs: Sequence[int],
    start: int,
    end: int,
    *,
    overlap_ratio: float,
    budget_chars: int,
) -> int:
    """
    Where the next window begins, backing up over the tail of this one.

    Walks back from the end taking whole segments until it has covered
    `overlap_ratio` of the window's own cost (the window's, not the budget's,
    so a short final window does not get a disproportionate share). Never backs
    up past `start + 1`: the next window must contain at least one segment this
    one did not, or the walk stalls.

    Rounding up to a whole segment can overshoot wildly when the tail segment
    is itself a large fraction of the budget — a 3000-character monologue
    dragged in as "10% overlap" halves what the next window can hold. So the
    overlap is then trimmed back from its front, and dropped entirely if even
    one segment is too fat to repeat. Losing boundary context is the lesser
    harm: that whole segment is intact in the previous window, whereas an
    over-stuffed next window degrades everything in it.
    """
    if overlap_ratio <= 0.0:
        return end

    window_cost = sum(costs[start:end])
    target = window_cost * overlap_ratio
    cap = budget_chars * MAX_OVERLAP_RATIO

    cursor = end
    covered = 0
    while cursor > start + 1 and covered < target:
        cursor -= 1
        covered += costs[cursor]

    while cursor < end and covered > cap:
        covered -= costs[cursor]
        cursor += 1

    return cursor


def _build_window(index: int, segments: Sequence[Segment]) -> TranscriptWindow:
    return TranscriptWindow(
        index=index,
        t0=min(s.t0 for s in segments),
        t1=max(s.t1 for s in segments),
        segments=tuple(segments),
    )
