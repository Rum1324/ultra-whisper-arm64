#!/usr/bin/env python3
"""
Python ctypes wrapper for whisper.cpp
Provides efficient in-memory transcription using libwhisper.dylib
"""

import ctypes
import os
from pathlib import Path
from typing import List, Dict, Optional
import numpy as np

# Load the whisper library
backend_dir = Path(__file__).parent
lib_path = backend_dir / "whisper.cpp" / "build" / "src" / "libwhisper.dylib"

if not lib_path.exists():
    raise FileNotFoundError(f"libwhisper.dylib not found at {lib_path}")

libwhisper = ctypes.CDLL(str(lib_path))


# Define structures
class WhisperContextParams(ctypes.Structure):
    _fields_ = [
        ("use_gpu", ctypes.c_bool),
        ("flash_attn", ctypes.c_bool),
        ("gpu_device", ctypes.c_int),
        ("dtw_token_timestamps", ctypes.c_bool),
        ("dtw_aheads_preset", ctypes.c_int),
        ("dtw_n_top", ctypes.c_int),
        ("dtw_aheads", ctypes.c_void_p),  # Simplified
        ("dtw_mem_size", ctypes.c_size_t),
    ]


# Opaque pointers
class WhisperContext(ctypes.Structure):
    pass


class WhisperState(ctypes.Structure):
    pass


# Nested structs for whisper_full_params
class _GreedyParams(ctypes.Structure):
    _fields_ = [("best_of", ctypes.c_int)]


class _BeamSearchParams(ctypes.Structure):
    _fields_ = [
        ("beam_size", ctypes.c_int),
        ("patience", ctypes.c_float),
    ]


class _WhisperVadParams(ctypes.Structure):
    _fields_ = [
        ("threshold", ctypes.c_float),
        ("min_speech_duration_ms", ctypes.c_int),
        ("min_silence_duration_ms", ctypes.c_int),
        ("max_speech_duration_s", ctypes.c_float),
        ("speech_pad_ms", ctypes.c_int),
        ("samples_overlap", ctypes.c_float),
    ]


class WhisperFullParams(ctypes.Structure):
    """
    Mirrors whisper_full_params from whisper.h exactly.
    Field order and types must match the C struct layout.
    """
    _fields_ = [
        ("strategy", ctypes.c_int),           # enum whisper_sampling_strategy
        ("n_threads", ctypes.c_int),
        ("n_max_text_ctx", ctypes.c_int),
        ("offset_ms", ctypes.c_int),
        ("duration_ms", ctypes.c_int),
        ("translate", ctypes.c_bool),
        ("no_context", ctypes.c_bool),
        ("no_timestamps", ctypes.c_bool),
        ("single_segment", ctypes.c_bool),
        ("print_special", ctypes.c_bool),
        ("print_progress", ctypes.c_bool),
        ("print_realtime", ctypes.c_bool),
        ("print_timestamps", ctypes.c_bool),
        ("token_timestamps", ctypes.c_bool),
        ("thold_pt", ctypes.c_float),
        ("thold_ptsum", ctypes.c_float),
        ("max_len", ctypes.c_int),
        ("split_on_word", ctypes.c_bool),
        ("max_tokens", ctypes.c_int),
        ("debug_mode", ctypes.c_bool),
        ("audio_ctx", ctypes.c_int),
        ("tdrz_enable", ctypes.c_bool),
        ("suppress_regex", ctypes.c_char_p),
        ("initial_prompt", ctypes.c_char_p),
        ("carry_initial_prompt", ctypes.c_bool),
        ("prompt_tokens", ctypes.c_void_p),   # const whisper_token*
        ("prompt_n_tokens", ctypes.c_int),
        ("language", ctypes.c_char_p),         # for auto-detect, set to None/""/b"auto"
        ("detect_language", ctypes.c_bool),
        ("suppress_blank", ctypes.c_bool),
        ("suppress_nst", ctypes.c_bool),
        ("temperature", ctypes.c_float),
        ("max_initial_ts", ctypes.c_float),
        ("length_penalty", ctypes.c_float),
        ("temperature_inc", ctypes.c_float),
        ("entropy_thold", ctypes.c_float),
        ("logprob_thold", ctypes.c_float),
        ("no_speech_thold", ctypes.c_float),
        ("greedy", _GreedyParams),
        ("beam_search", _BeamSearchParams),
        # Callbacks (function pointers, treated as void* since we don't use them)
        ("new_segment_callback", ctypes.c_void_p),
        ("new_segment_callback_user_data", ctypes.c_void_p),
        ("progress_callback", ctypes.c_void_p),
        ("progress_callback_user_data", ctypes.c_void_p),
        ("encoder_begin_callback", ctypes.c_void_p),
        ("encoder_begin_callback_user_data", ctypes.c_void_p),
        ("abort_callback", ctypes.c_void_p),
        ("abort_callback_user_data", ctypes.c_void_p),
        ("logits_filter_callback", ctypes.c_void_p),
        ("logits_filter_callback_user_data", ctypes.c_void_p),
        # Grammar
        ("grammar_rules", ctypes.c_void_p),
        ("n_grammar_rules", ctypes.c_size_t),
        ("i_start_rule", ctypes.c_size_t),
        ("grammar_penalty", ctypes.c_float),
        # VAD
        ("vad", ctypes.c_bool),
        ("vad_model_path", ctypes.c_char_p),
        ("vad_params", _WhisperVadParams),
    ]


# Function prototypes
libwhisper.whisper_context_default_params.restype = WhisperContextParams

libwhisper.whisper_init_from_file_with_params.argtypes = [
    ctypes.c_char_p,
    WhisperContextParams
]
libwhisper.whisper_init_from_file_with_params.restype = ctypes.POINTER(WhisperContext)

libwhisper.whisper_free.argtypes = [ctypes.POINTER(WhisperContext)]
libwhisper.whisper_free.restype = None

# Get default params by value (preferred — no manual memory management needed)
libwhisper.whisper_full_default_params.argtypes = [ctypes.c_int]
libwhisper.whisper_full_default_params.restype = WhisperFullParams

# Free params allocated by _by_ref variant (kept for completeness)
libwhisper.whisper_free_params.argtypes = [ctypes.c_void_p]
libwhisper.whisper_free_params.restype = None

libwhisper.whisper_full.argtypes = [
    ctypes.POINTER(WhisperContext),
    WhisperFullParams,             # params by value
    ctypes.POINTER(ctypes.c_float),
    ctypes.c_int
]
libwhisper.whisper_full.restype = ctypes.c_int

libwhisper.whisper_full_n_segments.argtypes = [ctypes.POINTER(WhisperContext)]
libwhisper.whisper_full_n_segments.restype = ctypes.c_int

libwhisper.whisper_full_get_segment_text.argtypes = [
    ctypes.POINTER(WhisperContext),
    ctypes.c_int
]
libwhisper.whisper_full_get_segment_text.restype = ctypes.c_char_p

libwhisper.whisper_full_get_segment_t0.argtypes = [
    ctypes.POINTER(WhisperContext),
    ctypes.c_int
]
libwhisper.whisper_full_get_segment_t0.restype = ctypes.c_int64

libwhisper.whisper_full_get_segment_t1.argtypes = [
    ctypes.POINTER(WhisperContext),
    ctypes.c_int
]
libwhisper.whisper_full_get_segment_t1.restype = ctypes.c_int64

libwhisper.whisper_full_lang_id.argtypes = [ctypes.POINTER(WhisperContext)]
libwhisper.whisper_full_lang_id.restype = ctypes.c_int

libwhisper.whisper_lang_id.argtypes = [ctypes.c_char_p]
libwhisper.whisper_lang_id.restype = ctypes.c_int

libwhisper.whisper_lang_str.argtypes = [ctypes.c_int]
libwhisper.whisper_lang_str.restype = ctypes.c_char_p


# Sampling strategy enum
WHISPER_SAMPLING_GREEDY = 0
WHISPER_SAMPLING_BEAM_SEARCH = 1


class WhisperModel:
    """High-level Python wrapper for whisper.cpp model"""

    def __init__(self, model_path: str, use_gpu: bool = True):
        """
        Initialize whisper model

        Args:
            model_path: Path to the .bin model file
            use_gpu: Whether to use GPU acceleration (Metal on macOS)
        """
        self.model_path = model_path

        # Get default context params
        cparams = libwhisper.whisper_context_default_params()
        cparams.use_gpu = use_gpu

        # Load model
        self.ctx = libwhisper.whisper_init_from_file_with_params(
            model_path.encode('utf-8'),
            cparams
        )

        if not self.ctx:
            raise RuntimeError(f"Failed to load model from {model_path}")

    def transcribe(
        self,
        audio: np.ndarray,
        language: Optional[str] = None,
        n_threads: int = 4
    ) -> Dict:
        """
        Transcribe audio using the loaded model

        Args:
            audio: Audio data as float32 numpy array (PCM, 16kHz, mono)
            language: Language code ('en', 'ja', etc.) or None/'auto' for auto-detect
            n_threads: Number of threads to use

        Returns:
            Dictionary with transcription results
        """
        # Ensure audio is float32
        if audio.dtype != np.float32:
            if audio.dtype == np.int16:
                # Convert int16 to float32 [-1.0, 1.0]
                audio = audio.astype(np.float32) / 32768.0
            else:
                audio = audio.astype(np.float32)

        # Get default transcription params (by value — clean Python struct, no raw offsets)
        params = libwhisper.whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

        # Set params by name (no fragile byte offsets)
        params.n_threads = n_threads
        params.translate = False   # transcribe only — never translate to English

        # Keep byte strings alive for the duration of the whisper_full call
        _lang_bytes = None

        if language and language not in ('auto', ''):
            lang_map = {
                'en': 'en',
                'english': 'en',
                'ja': 'ja',
                'japanese': 'ja',
            }
            lang_code = lang_map.get(language.lower(), language.lower())
            _lang_bytes = lang_code.encode('utf-8')
            params.language = _lang_bytes
            print(f"🎌 Language explicitly set to: {lang_code}")
        else:
            params.language = None  # whisper.cpp auto-detects when NULL
            print("🌍 Using auto-language detection")

        # Create pointer to audio data
        audio_ptr = audio.ctypes.data_as(ctypes.POINTER(ctypes.c_float))

        # Run transcription
        result = libwhisper.whisper_full(
            self.ctx,
            params,
            audio_ptr,
            len(audio)
        )

        if result != 0:
            raise RuntimeError(f"Transcription failed with code {result}")

        # Extract results
        n_segments = libwhisper.whisper_full_n_segments(self.ctx)

        segments = []
        full_text = ""

        for i in range(n_segments):
            text = libwhisper.whisper_full_get_segment_text(self.ctx, i)
            text = text.decode('utf-8') if text else ""

            t0 = libwhisper.whisper_full_get_segment_t0(self.ctx, i)
            t1 = libwhisper.whisper_full_get_segment_t1(self.ctx, i)

            # Convert from centiseconds to seconds
            t0_sec = t0 / 100.0
            t1_sec = t1 / 100.0

            segments.append({
                'text': text,
                't0': t0_sec,
                't1': t1_sec
            })

            full_text += text

        # Get detected language
        lang_id = libwhisper.whisper_full_lang_id(self.ctx)
        lang_str = libwhisper.whisper_lang_str(lang_id)
        detected_language = lang_str.decode('utf-8') if lang_str else 'unknown'

        # Debug output to verify language detection
        print(f"🔍 Detected language: {detected_language} (lang_id: {lang_id})")
        print(f"📝 Transcription preview: {full_text[:100] if full_text else '[empty]'}")

        return {
            'text': full_text.strip(),
            'segments': segments,
            'language': detected_language
        }

    def __del__(self):
        """Free the whisper context when the object is destroyed"""
        if hasattr(self, 'ctx') and self.ctx:
            libwhisper.whisper_free(self.ctx)
