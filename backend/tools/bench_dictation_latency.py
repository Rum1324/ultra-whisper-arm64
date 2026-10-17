#!/usr/bin/env python3
"""
Split the wait after the user stops talking into the backend's stages.

Exists because the app only logs whisper and AI formatting as two totals, which
cannot say where a >1 s dictation goes. This runs `transcribe_session` — the
code `end_session` takes — warm, on real clips, and times each stage inside it:
the speech gate, whisper (split into encoder passes from whisper.cpp's own
counters, and everything else: mel, decode, prompt, temperature fallbacks), the
rule pass, and AI formatting.

    PYTHONPATH=backend python3 backend/tools/bench_dictation_latency.py \
        --model ~/Library/Application\\ Support/UltraWhisper/models/ggml-large-v3-turbo.bin \
        [--wav F.wav ...] [--runs N] [--ai off|local|claude] [--ollama-host URL]

Modes per clip: `en` (language fixed), `auto` (the default setting), and
`auto+terms` (auto with a custom dictionary, which pre-detects the language).
`--ai claude` reads the key from ANTHROPIC_API_KEY. Formatting is warmed first,
as start_session does while the user speaks, so its number is a warm one.

Not covered: the client's side (stop cue, paste, keystrokes) and the WebSocket
hop, which is loopback. Load the model fresh from disk the first time; the
backend's own warm-up runs before any timed call.
"""
import argparse
import ctypes
import logging
import os
import re
import statistics
import sys
import tempfile
import time
import uuid
import wave
from functools import partial
from pathlib import Path

import numpy as np

import dictation_formatter
import server
from whisper_wrapper import libwhisper

BACKEND = Path(__file__).resolve().parent.parent
DEFAULT_WAVS = [
    BACKEND / "whisper.cpp" / "bindings" / "go" / "samples" / "jfk.wav",
    BACKEND.parent / "assets" / "audio_assets" / "Whisper_test_sample.wav",
]
TERMS = ["UltraWhisper", "Flutter", "Kubernetes"]
MODES = ["en", "auto", "auto+terms"]

_ENCODE_RE = re.compile(r"encode time =\s*([\d.]+) ms /\s*(\d+) runs")
_FALLBACK_RE = re.compile(r"fallbacks =\s*(\d+) p /\s*(\d+) h")


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path)) as w:
        if (w.getframerate(), w.getnchannels(), w.getsampwidth()) != (16000, 1, 2):
            sys.exit(f"{path}: need 16 kHz mono 16-bit PCM, like the app records")
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)


def quietly(fn):
    """Run fn with fd 1 and 2 captured (whisper.cpp logs to C stderr); return (result, text)."""
    sys.stdout.flush()
    sys.stderr.flush()
    saved = os.dup(1), os.dup(2)
    with tempfile.TemporaryFile() as tmp:
        os.dup2(tmp.fileno(), 1)
        os.dup2(tmp.fileno(), 2)
        try:
            result = fn()
            sys.stdout.flush()
            sys.stderr.flush()
        finally:
            os.dup2(saved[0], 1)
            os.dup2(saved[1], 2)
            os.close(saved[0])
            os.close(saved[1])
        tmp.seek(0)
        return result, tmp.read().decode("utf-8", "replace")


class StageTimer:
    """Wraps the functions transcribe_session calls, so each stage is timed in place."""

    def __init__(self, backend):
        self.times = {}
        server.check_speech = self.wrap("gate", server.check_speech)
        backend.model.transcribe = self.wrap("whisper", backend.model.transcribe)
        server.apply_post_processing = self.wrap("rules", server.apply_post_processing)
        dictation_formatter.format_dictation = self.wrap("ai", dictation_formatter.format_dictation)

    def wrap(self, name, fn):
        def timed(*args, **kwargs):
            started = time.perf_counter()
            try:
                return fn(*args, **kwargs)
            finally:
                self.times[name] = self.times.get(name, 0.0) + time.perf_counter() - started
        return timed


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--wav", nargs="*", type=Path, default=DEFAULT_WAVS)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--ai", choices=["off", "local", "claude"], default="off")
    parser.add_argument("--ollama-host", default=None)
    args = parser.parse_args()
    logging.disable(logging.INFO)  # per-session log lines would break up the table

    libwhisper.whisper_reset_timings.argtypes = [ctypes.c_void_p]
    libwhisper.whisper_print_timings.argtypes = [ctypes.c_void_p]

    backend, _ = quietly(lambda: server.WhisperCppBackend(args.model))
    quietly(backend.warm_up)
    timer = StageTimer(backend)

    post = {"aiFormatting": args.ai != "off"}
    if args.ai == "claude":
        post |= {"aiFormattingEngine": dictation_formatter.ENGINE_CLAUDE,
                 "anthropicApiKey": os.environ.get("ANTHROPIC_API_KEY")}
        if not post["anthropicApiKey"]:
            sys.exit("--ai claude needs ANTHROPIC_API_KEY")
    elif args.ai == "local":
        post |= {"aiFormattingEngine": dictation_formatter.ENGINE_LOCAL, "ollamaHost": args.ollama_host}

    print(f"model {args.model.name} | ai {args.ai} | median of {args.runs} warm runs\n")
    print(f"{'clip':28s} {'mode':10s} {'total':>7s} {'whisper':>8s} {'encode':>16s} {'rest':>6s} "
          f"{'gate':>6s} {'rules':>6s} {'ai':>6s} {'fb':>3s}  text")
    fallbacks_seen = 0
    for path in args.wav:
        audio = read_wav(path)
        for mode in MODES:
            rows = []
            for _ in range(args.runs):
                session_id = str(uuid.uuid4())
                config = {
                    "language": "en" if mode == "en" else None,
                    "post": post | {"customTerms": TERMS if mode == "auto+terms" else []},
                }
                session = backend.create_session(session_id, config)
                session.add_audio_chunk(audio.tobytes())
                if post["aiFormatting"]:
                    quietly(lambda: dictation_formatter.warm(
                        host=server.ollama_host(post.get("ollamaHost")),
                        engine=post.get("aiFormattingEngine", dictation_formatter.ENGINE_LOCAL),
                        api_key=post.get("anthropicApiKey")))
                timer.times = {}
                libwhisper.whisper_reset_timings(backend.model.ctx)
                started = time.perf_counter()
                result, _ = quietly(partial(backend.transcribe_session, session_id))
                total = time.perf_counter() - started
                _, log = quietly(lambda: libwhisper.whisper_print_timings(backend.model.ctx))
                backend.remove_session(session_id)
                enc = _ENCODE_RE.search(log)
                fb = _FALLBACK_RE.search(log)
                fallbacks = int(fb.group(1)) + int(fb.group(2)) if fb else 0
                rows.append({
                    "total": total,
                    "encode_s": float(enc.group(1)) / 1000 if enc else float("nan"),
                    "passes": int(enc.group(2)) if enc else -1,
                    "fallbacks": fallbacks - fallbacks_seen,
                    "text": result["text"],
                    **timer.times,
                })
                fallbacks_seen = fallbacks

            def med(key, rows=rows):
                return statistics.median(r.get(key, 0.0) for r in rows)

            passes = rows[-1]["passes"]
            encode = med("encode_s")
            whisper_s = med("whisper")
            print(f"{path.name[:28]:28s} {mode:10s} {med('total'):6.2f}s {whisper_s:7.2f}s "
                  f"{passes:>2d}x{1000 * encode / max(passes, 1):5.0f}ms={encode:4.2f}s "
                  f"{whisper_s - encode:5.2f}s {med('gate'):5.3f}s {med('rules'):5.3f}s "
                  f"{med('ai'):5.2f}s {sum(r['fallbacks'] for r in rows):>3d}  {rows[-1]['text'][:40]!r}")
    print("\nencode = encoder passes x time per pass; rest = mel + decode + prompt + fallbacks;"
          "\nfb = temperature fallbacks across the runs (each one re-decodes the window).")



if __name__ == "__main__":
    main()
