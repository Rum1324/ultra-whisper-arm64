"""The dictation energy gate: keep whispers, drop silence."""

import numpy as np

from speech_gate import check_speech

SAMPLE_RATE = 16000
RNG = np.random.default_rng(0)


def _noise(seconds: float, rms: float) -> np.ndarray:
    return RNG.normal(0, rms, int(seconds * SAMPLE_RATE))


def _pcm(x: np.ndarray) -> np.ndarray:
    return np.clip(x * 32768, -32768, 32767).astype(np.int16)


def _whisper(peak_rms: float, floor_rms: float) -> np.ndarray:
    """Toggle-mode shape: room tone, three whispered words with gaps, room tone.

    A whisper is unvoiced, so noise bursts are a fair stand-in for its energy.
    """
    parts = [_noise(1.0, floor_rms)]
    for _ in range(3):
        parts += [_noise(0.3, peak_rms), _noise(0.25, floor_rms)]
    parts.append(_noise(1.0, floor_rms))
    return _pcm(np.concatenate(parts))


def test_quiet_whisper_passes():
    # Peak below the old absolute 0.01 gate, which dropped it.
    result = check_speech(_whisper(peak_rms=0.005, floor_rms=0.0005))
    assert result.peak_rms < 0.01
    assert result.has_speech


def test_loud_speech_passes():
    assert check_speech(_whisper(peak_rms=0.05, floor_rms=0.003)).has_speech


def test_anything_the_old_gate_kept_still_passes():
    # A loud clip with no floor contrast at all (wall-to-wall speech).
    assert check_speech(_pcm(_noise(2.0, 0.02))).has_speech


def test_room_tone_is_rejected():
    # Measured on a Hollyland lavalier in a quiet room: floor ≈ 0.002.
    for rms in (0.001, 0.003, 0.008):
        assert not check_speech(_pcm(_noise(4.0, rms))).has_speech


def test_single_click_is_rejected():
    audio = _noise(3.0, 0.0005)
    audio[SAMPLE_RATE : SAMPLE_RATE + 480] = _noise(0.03, 0.008)
    assert not check_speech(_pcm(audio)).has_speech


def test_digital_silence_is_rejected():
    assert not check_speech(np.zeros(SAMPLE_RATE * 2, dtype=np.int16)).has_speech


def test_empty_audio_is_rejected():
    assert not check_speech(np.zeros(0, dtype=np.int16)).has_speech
