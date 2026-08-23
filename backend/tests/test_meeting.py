#!/usr/bin/env python3
"""
Tests for `meeting`: track framing, rolling windows, absolute timestamps.

No whisper and no websockets anywhere — the module is written so the windowing
can be exercised without loading a 1.5 GB model, and these tests are the reason
it is written that way.

The alignment cases are the point of this file. Two tracks arriving at slightly
different rates is the normal condition, not an edge case, and getting the
window boundary wrong shows up as a transcript whose speakers drift apart.
"""

import numpy as np
import pytest

from meeting import (
    BYTES_PER_SAMPLE,
    SAMPLE_RATE,
    TRACK_MIC,
    TRACK_SYSTEM,
    MeetingSession,
    build_window,
    peak_window_rms,
    split_audio_frame,
)


def _pcm(seconds: float, amplitude: int = 1000) -> bytes:
    count = int(seconds * SAMPLE_RATE)
    return (np.ones(count, dtype=np.int16) * amplitude).tobytes()


def _session(**kwargs) -> MeetingSession:
    kwargs.setdefault("window_seconds", 1)
    return MeetingSession("m1", **kwargs)


# ---------------------------------------------------------------------------
# Framing
# ---------------------------------------------------------------------------


def test_split_audio_frame_reads_track_and_body():
    track, body = split_audio_frame(bytes([TRACK_SYSTEM]) + _pcm(0.01))
    assert track == TRACK_SYSTEM
    assert len(body) == int(0.01 * SAMPLE_RATE) * BYTES_PER_SAMPLE


def test_unknown_track_tag_is_rejected():
    """Silently accepting an unknown tag would put audio on the wrong speaker."""
    with pytest.raises(ValueError, match="unknown track"):
        split_audio_frame(b"\x07" + _pcm(0.01))


def test_odd_length_body_is_rejected():
    """A half sample means the stream is misaligned; shifted noise, not speech."""
    with pytest.raises(ValueError, match="int16"):
        split_audio_frame(bytes([TRACK_MIC]) + b"\x00\x01\x02")


def test_empty_frame_is_rejected():
    with pytest.raises(ValueError):
        split_audio_frame(b"")


# ---------------------------------------------------------------------------
# Windowing
# ---------------------------------------------------------------------------


def test_window_not_ready_until_filled():
    s = _session()
    s.add_audio(TRACK_MIC, _pcm(0.5))
    assert s.pop_ready_window() is None


def test_window_ready_when_both_tracks_cover_it():
    s = _session()
    s.add_audio(TRACK_MIC, _pcm(1.0))
    s.add_audio(TRACK_SYSTEM, _pcm(1.0))
    window = s.pop_ready_window()
    assert window is not None
    assert window.index == 0
    assert (window.t0, window.t1) == (0.0, 1.0)
    assert set(window.tracks) == {TRACK_MIC, TRACK_SYSTEM}


def test_waits_for_the_slower_track():
    """
    Alignment is driven by the SLOWEST active track.

    Emitting as soon as the fastest track covers the boundary would clip
    whichever one lagged — and lagging by a chunk is the normal condition.
    """
    s = _session()
    s.add_audio(TRACK_MIC, _pcm(1.0))
    s.add_audio(TRACK_SYSTEM, _pcm(0.9))
    assert s.pop_ready_window() is None

    s.add_audio(TRACK_SYSTEM, _pcm(0.1))
    assert s.pop_ready_window() is not None


def test_single_active_track_is_not_held_for_a_silent_one():
    """A meeting with no system capture must still produce windows."""
    s = _session()
    s.add_audio(TRACK_MIC, _pcm(1.0))
    window = s.pop_ready_window()
    assert window is not None
    assert set(window.tracks) == {TRACK_MIC}


def test_stalled_track_does_not_stall_the_meeting():
    """
    A track that stops — screen share ended — never reaches the boundary.

    Waiting on it forever would freeze the transcript, so a track a full window
    behind the leader stops being held for.
    """
    s = _session()
    s.add_audio(TRACK_SYSTEM, _pcm(0.2))  # marks the track active, then stops
    s.add_audio(TRACK_MIC, _pcm(1.0))
    assert s.pop_ready_window() is None, "one window of lag is tolerated"

    s.add_audio(TRACK_MIC, _pcm(1.0))
    window = s.pop_ready_window()
    assert window is not None, "two windows of lag means the track has stalled"


def test_windows_advance_and_stamp_consecutively():
    s = _session()
    s.add_audio(TRACK_MIC, _pcm(3.0))
    s.add_audio(TRACK_SYSTEM, _pcm(3.0))
    stamps = []
    while (w := s.pop_ready_window()) is not None:
        stamps.append((w.index, w.t0, w.t1))
    assert stamps == [(0, 0.0, 1.0), (1, 1.0, 2.0), (2, 2.0, 3.0)]


def test_audio_is_discarded_after_a_window_is_taken():
    """
    The whole reason meetings do not buffer like dictation.

    An hour of two-track audio is hundreds of megabytes; a meeting is expected
    to stay open for hours.
    """
    s = _session()
    s.add_audio(TRACK_MIC, _pcm(2.0))
    s.add_audio(TRACK_SYSTEM, _pcm(2.0))
    s.pop_ready_window()
    held = sum(len(b) for b in s._buffers.values())
    assert held == 2 * int(1.0 * SAMPLE_RATE) * BYTES_PER_SAMPLE, "only the unwindowed second remains"


def test_flush_returns_the_trailing_partial_window():
    s = _session()
    s.add_audio(TRACK_MIC, _pcm(0.4))
    assert s.pop_ready_window() is None
    window = s.flush()
    assert window is not None
    assert window.index == 0
    assert len(window.tracks[TRACK_MIC]) == int(0.4 * SAMPLE_RATE)


def test_flush_on_an_exact_boundary_returns_nothing():
    """Lets the caller tell a remainder from a meeting that ended on the grid."""
    s = _session()
    s.add_audio(TRACK_MIC, _pcm(1.0))
    s.add_audio(TRACK_SYSTEM, _pcm(1.0))
    s.pop_ready_window()
    assert s.flush() is None


def test_short_track_does_not_shift_later_windows():
    """
    A track that fell short still advances to the window grid.

    Otherwise the shortfall is carried forward and that track's later audio is
    stamped early by the gap — a drift that lasts the rest of the meeting.

    Asserted on the audio CONTENT, not the window index: the index comes from a
    counter that a cursor bug does not move, so checking it would pass either
    way. The two tracks carry distinct amplitudes so the samples can be told
    apart once they land in a window.
    """
    early, late = 111, 222
    s = _session()
    s.add_audio(TRACK_SYSTEM, _pcm(0.3, early))  # goes quiet mid-window
    s.add_audio(TRACK_MIC, _pcm(2.0))

    first = s.pop_ready_window()
    assert first is not None, "the stall rule should force window 0 out"
    assert np.all(first.tracks[TRACK_SYSTEM] == early)

    # The system track comes back, starting at the second window's boundary.
    s.add_audio(TRACK_SYSTEM, _pcm(1.0, late))
    second = s.pop_ready_window()

    assert second is not None, "a stale cursor leaves this track short forever"
    assert second.index == 1
    assert second.t0 == 1.0
    assert np.all(second.tracks[TRACK_SYSTEM] == late), "window 1 must hold window 1's audio"
    assert len(second.tracks[TRACK_SYSTEM]) == SAMPLE_RATE


# ---------------------------------------------------------------------------
# Timestamps and merging
# ---------------------------------------------------------------------------


def test_build_window_makes_timestamps_absolute():
    """
    Whisper restarts segment times at zero on every call.

    Adding the window offset here is the only thing that makes
    `contracts.Segment`'s absolute-time guarantee true.
    """
    window = build_window(
        3,
        360.0,
        480.0,
        {TRACK_MIC: [{"text": "hello", "t0": 12.4, "t1": 15.1}]},
    )
    assert window.segments[0].t0 == 372.4
    assert window.segments[0].t1 == 375.1


def test_build_window_maps_tracks_to_speakers():
    """Attribution is physical: track 0 is me, track 1 is them."""
    window = build_window(
        0,
        0.0,
        120.0,
        {
            TRACK_MIC: [{"text": "mine", "t0": 1.0, "t1": 2.0}],
            TRACK_SYSTEM: [{"text": "theirs", "t0": 3.0, "t1": 4.0}],
        },
    )
    by_speaker = {s.speaker: s.text for s in window.segments}
    assert by_speaker == {"me": "mine", "them": "theirs"}


def test_build_window_interleaves_tracks_by_time():
    window = build_window(
        0,
        0.0,
        120.0,
        {
            TRACK_MIC: [{"text": "first", "t0": 1.0, "t1": 2.0}, {"text": "third", "t0": 9.0, "t1": 9.5}],
            TRACK_SYSTEM: [{"text": "second", "t0": 4.0, "t1": 5.0}],
        },
    )
    assert [s.text for s in window.segments] == ["first", "second", "third"]


def test_build_window_drops_blank_segments():
    """Whisper emits empty segments for silence; they are not conversation."""
    window = build_window(
        0, 0.0, 120.0, {TRACK_MIC: [{"text": "   ", "t0": 1.0, "t1": 2.0}]}
    )
    assert window.segments == ()


def test_recorded_segments_accumulate_across_windows():
    s = _session()
    s.record(build_window(0, 0.0, 1.0, {TRACK_MIC: [{"text": "a", "t0": 0.1, "t1": 0.2}]}))
    s.record(build_window(1, 1.0, 2.0, {TRACK_SYSTEM: [{"text": "b", "t0": 0.1, "t1": 0.2}]}))
    transcript = s.transcript()
    assert [seg.text for seg in transcript] == ["a", "b"]
    assert [seg.t0 for seg in transcript] == [0.1, 1.1]
    assert [seg.speaker for seg in transcript] == ["me", "them"]


# ---------------------------------------------------------------------------
# VAD
# ---------------------------------------------------------------------------


def test_peak_rms_ignores_surrounding_silence():
    """
    A meeting window is mostly silence on at least one track.

    A whole-clip average would drop a real utterance for being surrounded by
    quiet, which is exactly the shape of one side of a conversation.
    """
    # Quiet, brief speech in a long silence: loud enough to hear, soft
    # enough that averaging over the window buries it.
    speech = (np.ones(SAMPLE_RATE // 10, dtype=np.int16) * 2000)
    silence = np.zeros(SAMPLE_RATE * 5, dtype=np.int16)
    clip = np.concatenate([silence, speech, silence])

    assert peak_window_rms(clip) > 0.01
    whole_clip_mean = float(np.sqrt(np.mean((clip.astype(np.float32) / 32768.0) ** 2)))
    assert whole_clip_mean < 0.01, "the average would have dropped this"


def test_peak_rms_of_pure_silence_is_zero():
    assert peak_window_rms(np.zeros(SAMPLE_RATE, dtype=np.int16)) == 0.0


def test_peak_rms_of_empty_audio_is_zero():
    assert peak_window_rms(np.zeros(0, dtype=np.int16)) == 0.0
