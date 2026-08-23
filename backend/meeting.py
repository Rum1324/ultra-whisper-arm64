#!/usr/bin/env python3
"""
Meeting sessions: two-track buffering, rolling windows, absolute timestamps.

This is the state behind `start_meeting` / `end_meeting` in
docs/MEETING_PROTOCOL.md. It is deliberately free of whisper and of
websockets — `server.py` supplies a transcribe callable and does the sending —
so the windowing logic can be tested without loading a 1.5 GB model.

Why the audio is discarded as it goes, rather than buffered like dictation:

`TranscriptionSession.audio_buffer` is a plain Python list built with
`.extend(numpy_array)`. One hour of mono 16 kHz is 57.6M elements — roughly
460 MB in pointers alone versus 115 MB as int16, doubled for two tracks, and
`get_audio_array()` copies the lot again. A meeting is expected to stay open for
hours, so it retains stamped text and throws the audio away once transcribed.

Why timestamps are computed here rather than taken from whisper: whisper.cpp
restarts segment times at zero on every `whisper_full()` call, so a meeting
transcribed as a series of windows produces many segments that each believe
they start at 0s. The window offset is added before a `Segment` is built, which
is what makes `contracts.Segment`'s "absolute from the start of the meeting"
guarantee true.

Speaker attribution is physical, not inferred. There is no diarization
anywhere in UltraWhisper: track 0 is the microphone and is "me", track 1 is the
system capture and is "them". That is the entire reason two tracks are captured.
"""

import logging
from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import numpy as np

from summarize.contracts import Segment, TranscriptWindow

logger = logging.getLogger(__name__)

# Track tags, as they appear in byte 0 of a meeting audio frame.
TRACK_MIC = 0x00
TRACK_SYSTEM = 0x01

# Which speaker label each track carries. See the module docstring: this is a
# physical mapping, not a guess.
TRACK_SPEAKERS: Dict[int, str] = {
    TRACK_MIC: "me",
    TRACK_SYSTEM: "them",
}

SAMPLE_RATE = 16000
BYTES_PER_SAMPLE = 2

# Default rolling window, matching `windowSeconds` in the protocol.
DEFAULT_WINDOW_SECONDS = 120

# Below this, a window is too short to be worth a whisper call at all. Same
# 0.1s floor `transcribe_session` uses for dictation.
MIN_WINDOW_SAMPLES = 1600

# Energy VAD threshold, and the frame it is measured over. Deliberately a copy
# of the dictation path's constants rather than a shared import: the protocol
# states that any change altering single-shot dictation output is a regression,
# and the safest way to honour that is to not touch that code path at all.
VAD_FRAME_SAMPLES = 480  # 30 ms @ 16 kHz
VAD_PEAK_RMS_THRESHOLD = 0.01


def peak_window_rms(audio: np.ndarray) -> float:
    """
    RMS of the LOUDEST 30 ms frame, not of the whole clip.

    A meeting window is mostly silence on at least one track — the other person
    is talking — so a whole-clip average would drop real speech that happens to
    be surrounded by quiet. Measuring the peak frame is silence-invariant, so
    this only ever keeps more audio than an average would.
    """
    if audio.size == 0:
        return 0.0
    audio_float = audio.astype(np.float32) / 32768.0
    n_frames = len(audio_float) // VAD_FRAME_SAMPLES
    if n_frames == 0:
        return float(np.sqrt(np.mean(audio_float**2)))
    frames = audio_float[: n_frames * VAD_FRAME_SAMPLES].reshape(n_frames, VAD_FRAME_SAMPLES)
    return float(np.sqrt(np.mean(frames**2, axis=1)).max())


def split_audio_frame(payload: bytes) -> Tuple[int, bytes]:
    """
    Split a meeting audio frame into its track tag and PCM body.

    Meeting frames carry one leading track byte; dictation frames are bare PCM.
    One byte rather than a JSON sidecar because these arrive every 20-40 ms for
    the length of a meeting.

    Raises `ValueError` on a frame that cannot be interpreted — an unknown tag,
    or a body that is not whole int16 samples. Silently accepting either would
    put shifted noise into the transcript.
    """
    if len(payload) < 1:
        raise ValueError("empty audio frame")
    track = payload[0]
    if track not in TRACK_SPEAKERS:
        raise ValueError(f"unknown track tag 0x{track:02x}")
    body = payload[1:]
    if len(body) % BYTES_PER_SAMPLE:
        raise ValueError(f"PCM body of {len(body)} bytes is not whole int16 samples")
    return track, body


@dataclass
class PendingWindow:
    """One window's audio, ready to transcribe, with the offset to stamp it by."""

    index: int
    t0: float
    t1: float
    tracks: Dict[int, np.ndarray]


def build_window(
    index: int,
    t0: float,
    t1: float,
    per_track_segments: Dict[int, Sequence[Dict[str, Any]]],
) -> TranscriptWindow:
    """
    Turn whisper's per-track output into one interleaved, absolutely-stamped window.

    Whisper hands back `{'text', 't0', 't1'}` with times relative to the buffer
    it was given, so `t0` is added here — that offset is the only thing making
    the timestamps absolute, since whisper restarts them at zero each call.

    The merge by `t0` across tracks is where the interleaved conversation comes
    from. There is no diarization involved; the tracks were already separate.
    """
    merged: List[Segment] = []
    for track, segments in per_track_segments.items():
        speaker = TRACK_SPEAKERS.get(track)
        if speaker is None:
            continue
        for raw in segments:
            text = (raw.get("text") or "").strip()
            if not text:
                continue
            merged.append(
                Segment(
                    t0=t0 + float(raw.get("t0", 0.0)),
                    t1=t0 + float(raw.get("t1", 0.0)),
                    speaker=speaker,
                    text=text,
                )
            )

    # Stable sort, so two segments starting at the same instant keep a
    # deterministic order rather than shuffling between runs.
    merged.sort(key=lambda s: s.t0)
    return TranscriptWindow(index=index, t0=t0, t1=t1, segments=tuple(merged))


class MeetingSession:
    """
    A meeting's live state: two audio buffers in, stamped segments out.

    Safe to leave open for hours — see the module docstring for why the audio
    does not accumulate.
    """

    def __init__(
        self,
        meeting_id: str,
        *,
        meeting_type: str = "generic",
        language: Optional[str] = None,
        title: Optional[str] = None,
        window_seconds: int = DEFAULT_WINDOW_SECONDS,
        sample_rate: int = SAMPLE_RATE,
    ) -> None:
        self.meeting_id = meeting_id
        self.meeting_type = meeting_type
        self.language = language
        self.title = title
        self.window_seconds = max(1, int(window_seconds))
        self.sample_rate = sample_rate
        self.is_active = True

        # Absolute segments, retained for the whole meeting. This is the only
        # thing that grows without bound, and it grows as text.
        self.segments: List[Segment] = []

        self._buffers: Dict[int, bytearray] = {TRACK_MIC: bytearray(), TRACK_SYSTEM: bytearray()}
        # Absolute sample index each buffer now starts at; equals
        # windows_emitted * samples_per_window once a track has been consumed.
        self._cursor: Dict[int, int] = {TRACK_MIC: 0, TRACK_SYSTEM: 0}
        self._seen: Dict[int, bool] = {TRACK_MIC: False, TRACK_SYSTEM: False}
        self._next_index = 0

    # -- accounting ---------------------------------------------------------

    @property
    def samples_per_window(self) -> int:
        return self.window_seconds * self.sample_rate

    def _available(self, track: int) -> int:
        """Absolute sample index this track has data up to."""
        return self._cursor[track] + len(self._buffers[track]) // BYTES_PER_SAMPLE

    def _active_tracks(self) -> List[int]:
        return [t for t, seen in self._seen.items() if seen]

    # -- input --------------------------------------------------------------

    def add_audio(self, track: int, pcm: bytes) -> None:
        """Append PCM int16 LE mono 16 kHz for one track."""
        if track not in self._buffers:
            raise ValueError(f"unknown track {track}")
        self._buffers[track].extend(pcm)
        self._seen[track] = True

    # -- windowing ----------------------------------------------------------

    def pop_ready_window(self) -> Optional[PendingWindow]:
        """
        Take the next complete window, or None if it is not filled yet.

        A window is ready once EVERY track that has ever sent audio covers its
        end. Waiting for the slowest active track is what keeps the two tracks
        aligned; using the fastest would clip whichever one lagged by a chunk.

        The exception is a track that has STOPPED — the user ended the screen
        share, say. That track never reaches the boundary, and waiting on it
        would stall the meeting permanently. So a track more than one whole
        window behind the leader is treated as stalled and no longer held for.
        """
        active = self._active_tracks()
        if not active:
            return None

        end = (self._next_index + 1) * self.samples_per_window
        slowest = min(self._available(t) for t in active)
        fastest = max(self._available(t) for t in active)

        if slowest < end:
            stalled = fastest >= end + self.samples_per_window
            if not stalled:
                return None
            logger.warning(
                "meeting %s: a track is a full window behind; emitting window %d without it",
                self.meeting_id,
                self._next_index,
            )

        return self._take_window()

    def flush(self) -> Optional[PendingWindow]:
        """
        Take the trailing partial window at `end_meeting`.

        Returns None when nothing is left, so the caller can tell "meeting had a
        remainder" from "meeting ended exactly on a boundary".
        """
        if not any(self._buffers[t] for t in self._buffers):
            return None
        return self._take_window()

    def _take_window(self) -> PendingWindow:
        index = self._next_index
        spw = self.samples_per_window
        want = spw * BYTES_PER_SAMPLE
        t0 = float(index * self.window_seconds)

        tracks: Dict[int, np.ndarray] = {}
        for track, buffer in self._buffers.items():
            chunk = bytes(buffer[:want])
            del buffer[: len(chunk)]
            self._cursor[track] += len(chunk) // BYTES_PER_SAMPLE
            if chunk:
                tracks[track] = np.frombuffer(chunk, dtype=np.int16)

        # A track that fell short still advances to the window grid, or every
        # later window on that track would be stamped early by the shortfall.
        for track in self._buffers:
            self._cursor[track] = max(self._cursor[track], (index + 1) * spw)

        self._next_index += 1
        return PendingWindow(index=index, t0=t0, t1=t0 + float(self.window_seconds), tracks=tracks)

    # -- output -------------------------------------------------------------

    def record(self, window: TranscriptWindow) -> TranscriptWindow:
        """Retain a transcribed window's segments and return it unchanged."""
        self.segments.extend(window.segments)
        return window

    def transcript(self) -> List[Segment]:
        """Every segment so far, in meeting order."""
        return list(self.segments)
