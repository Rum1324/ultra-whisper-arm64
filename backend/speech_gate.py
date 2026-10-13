"""
Energy gate for dictation: decide whether a clip has speech worth a whisper call.

The gate exists to stop whisper hallucinating on silence ("ご視聴ありがとう
ございました", "Thank you."). It used to be a single absolute test — the loudest
30 ms window must reach RMS 0.01 — which a clip-on mic fails when the speaker
whispers: a whispered sentence on a Hollyland lavalier peaked at 0.026, and the
same sentence 9 dB softer (a lower clip position, a softer whisper) peaked at
0.009 and was thrown away, although whisper still transcribed it word for word
at 12 dB softer.

What separates a whisper from silence is not its absolute level but its
contrast with the clip's own noise floor. So a clip passes when either:

- its loudest window reaches the old absolute threshold (every clip that passed
  before still passes), or
- enough of it — 300 ms in all — stands well above its noise floor (the 10th
  percentile window, i.e. the pauses between words and the silence padding a
  toggle recording always has), and above an absolute floor that digital
  silence and a dead input never reach.

Stationary hiss has no such contrast, and a single click is too short.
"""

from dataclasses import dataclass

import numpy as np

FRAME_SAMPLES = 480  # 30 ms @ 16 kHz

# The original absolute gate. Anything this loud is speech-level.
LOUD_PEAK_RMS = 0.01

# Quiet path: a window counts as speech when it is this many times the noise
# floor (3x ≈ +9.5 dB) and at least QUIET_MIN_RMS (-54 dBFS).
FLOOR_PERCENTILE = 10
QUIET_FLOOR_RATIO = 3.0
QUIET_MIN_RMS = 0.002
QUIET_MIN_SPEECH_FRAMES = 10  # 300 ms


@dataclass(frozen=True)
class GateResult:
    has_speech: bool
    peak_rms: float
    floor_rms: float
    speech_ms: int

    def describe(self) -> str:
        return (
            f"peak 30ms RMS={self.peak_rms:.4f}, floor={self.floor_rms:.4f}, "
            f"speech≈{self.speech_ms}ms"
        )


def frame_rms(audio: np.ndarray) -> np.ndarray:
    """RMS of each 30 ms frame of int16 (or float [-1, 1]) audio."""
    if audio.dtype == np.int16:
        audio = audio.astype(np.float32) / 32768.0
    else:
        audio = audio.astype(np.float32)
    n_frames = len(audio) // FRAME_SAMPLES
    if n_frames == 0:
        if audio.size == 0:
            return np.zeros(0, dtype=np.float32)
        return np.array([np.sqrt(np.mean(audio**2))], dtype=np.float32)
    frames = audio[: n_frames * FRAME_SAMPLES].reshape(n_frames, FRAME_SAMPLES)
    return np.sqrt(np.mean(frames**2, axis=1))


def check_speech(audio: np.ndarray) -> GateResult:
    rms = frame_rms(audio)
    if rms.size == 0:
        return GateResult(False, 0.0, 0.0, 0)

    peak = float(rms.max())
    floor = float(np.percentile(rms, FLOOR_PERCENTILE))
    threshold = max(QUIET_MIN_RMS, QUIET_FLOOR_RATIO * floor)
    speech_frames = int(np.count_nonzero(rms >= threshold))
    speech_ms = speech_frames * FRAME_SAMPLES * 1000 // 16000

    has_speech = peak >= LOUD_PEAK_RMS or speech_frames >= QUIET_MIN_SPEECH_FRAMES
    return GateResult(has_speech, peak, floor, speech_ms)
