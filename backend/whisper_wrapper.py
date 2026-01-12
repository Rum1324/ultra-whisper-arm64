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


# Function prototypes
libwhisper.whisper_context_default_params.restype = WhisperContextParams

libwhisper.whisper_init_from_file_with_params.argtypes = [
    ctypes.c_char_p,
    WhisperContextParams
]
libwhisper.whisper_init_from_file_with_params.restype = ctypes.POINTER(WhisperContext)

libwhisper.whisper_free.argtypes = [ctypes.POINTER(WhisperContext)]
libwhisper.whisper_free.restype = None

# We need a reference to whisper_full_params, but it's complex
# So we'll use the C function to get default params
libwhisper.whisper_full_default_params_by_ref.argtypes = [ctypes.c_int]
libwhisper.whisper_full_default_params_by_ref.restype = ctypes.c_void_p

libwhisper.whisper_full.argtypes = [
    ctypes.POINTER(WhisperContext),
    ctypes.c_void_p,  # whisper_full_params pointer
    ctypes.POINTER(ctypes.c_float),  # audio data
    ctypes.c_int  # number of samples
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
            language: Language code ('en', 'ja', 'auto', etc.) or None for auto-detect
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

        # Get default transcription params
        # Use greedy sampling (0)
        params_ptr = libwhisper.whisper_full_default_params_by_ref(
            WHISPER_SAMPLING_GREEDY
        )

        # Use simple byte offset approach (this works!)
        # The struct starts with strategy, then n_threads at offset 4
        params_bytes = ctypes.cast(params_ptr, ctypes.POINTER(ctypes.c_int))
        params_bytes[1] = n_threads  # n_threads is second field

        # Set translate to false (offset 20) - we want transcription, not translation!
        # This ensures we get Japanese as Japanese, not translated to English
        translate_ptr = ctypes.cast(
            ctypes.addressof(ctypes.cast(params_ptr, ctypes.POINTER(ctypes.c_char)).contents) + 20,
            ctypes.POINTER(ctypes.c_bool)
        )
        translate_ptr[0] = False

        # Set language if specified (simple approach)
        if language and language != 'auto':
            # Map language codes
            lang_map = {
                'en': 'en',
                'english': 'en',
                'ja': 'ja',
                'japanese': 'ja',
            }
            lang_code = lang_map.get(language.lower(), language.lower())

            # Get language ID using whisper.cpp function
            lang_id = libwhisper.whisper_lang_id(lang_code.encode('utf-8'))

            # Set the language in params using simple offset (language field is at offset 48 in the struct)
            # This is a simpler approach than the complex one we had before
            lang_ptr = ctypes.cast(
                ctypes.addressof(ctypes.cast(params_ptr, ctypes.POINTER(ctypes.c_char)).contents) + 48,
                ctypes.POINTER(ctypes.c_char)
            )
            # Copy the language code string
            for i, c in enumerate(lang_code.encode('utf-8')):
                lang_ptr[i] = c
            lang_ptr[len(lang_code)] = 0  # Null terminate

            print(f"🎌 Language explicitly set to: {lang_code} (id: {lang_id})")
        else:
            print("🌍 Using auto-language detection")

        # Create pointer to audio data
        audio_ptr = audio.ctypes.data_as(ctypes.POINTER(ctypes.c_float))

        # Run transcription
        result = libwhisper.whisper_full(
            self.ctx,
            params_ptr,
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
