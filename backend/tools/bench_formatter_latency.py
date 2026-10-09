#!/usr/bin/env python3
"""
Time AI formatting against a live Ollama: cold, preloaded mid-speech, and warm.

Exists because the unit tests stub the model, so they cannot see the one thing
users feel — gemma4:e4b being evicted (keep_alive ran out, Ollama restarted,
memory pressure) and the next dictation paying the load. A load that outlasts
`timeout_for(text)` does not error: `format_dictation` quietly returns the
rule-based text with source "timeout", and the user just sees no formatting.

    PYTHONPATH=backend python3 backend/tools/bench_formatter_latency.py [--host URL] [--runs N] [--speech S]

Scenarios, each starting from an unloaded model except `warm`:

* cold  — no preload at all; the worst case (preload failed, or the dictation
          was shorter than the load).
* race  — what server.py does: `warm()` fires at start_session, the user speaks
          for `--speech` seconds, then `format_dictation` runs. The number is
          what the user waits AFTER they stop talking.
* warm  — model already resident; the floor.

Unloading evicts the model from that Ollama for everyone, including a running
UltraWhisper; it reloads on the next dictation. "Cold" here means evicted from
Ollama, not from the OS page cache — a true disk-cold load (after a reboot) is
slower still and needs `sudo purge` to reproduce.

Exits non-zero when `verdict` says the user-facing latency is not acceptable.
"""
import argparse
import statistics
import sys
import threading
import time
from dataclasses import dataclass

import dictation_formatter as fmt
from summarize.contracts import Unavailable
from summarize.llm import DEFAULT_HOST, unload

SAMPLES = [
    ("en", "um so I think we should uh move the standup to ten thirty because the the design review keeps running over"),
    ("ja", "えーと 明日の会議なんですけど あの 3時からじゃなくて4時からに変更してもらえますか"),
]


@dataclass
class Run:
    scenario: str
    lang: str
    seconds: float
    source: str  # FormatResult.source: "llm", "timeout", "rejected: ...", ...
    timeout: float


def _evict(host: str) -> None:
    result = unload(model=fmt.DEFAULT_MODEL, host=host)
    if isinstance(result, Unavailable):
        sys.exit(f"Could not unload {fmt.DEFAULT_MODEL} from {host}: {result.detail}")


def _timed_format(text: str, host: str) -> tuple[float, str]:
    start = time.monotonic()
    result = fmt.format_dictation(text, host=host)
    return time.monotonic() - start, result.source


def run_cold(lang: str, text: str, host: str) -> Run:
    _evict(host)
    seconds, source = _timed_format(text, host)
    return Run("cold", lang, seconds, source, fmt.timeout_for(text))


def run_race(lang: str, text: str, host: str, speech_s: float) -> Run:
    _evict(host)
    threading.Thread(target=fmt.warm, kwargs={"host": host}, daemon=True).start()
    time.sleep(speech_s)
    seconds, source = _timed_format(text, host)
    return Run("race", lang, seconds, source, fmt.timeout_for(text))


def run_warm(lang: str, text: str, host: str) -> Run:
    fmt.warm(host=host)
    seconds, source = _timed_format(text, host)
    return Run("warm", lang, seconds, source, fmt.timeout_for(text))


def time_load(host: str) -> float:
    """Load alone, no generation: how much of `cold` is the load."""
    _evict(host)
    start = time.monotonic()
    if not fmt.warm(host=host):
        sys.exit(f"{fmt.DEFAULT_MODEL} did not load on {host}; is it pulled?")
    return time.monotonic() - start


def verdict(runs: list[Run], load_s: list[float], speech_s: float) -> list[str]:
    """
    Return one line per problem; an empty list means acceptable.

    `runs` holds every measured dictation (scenario, lang, seconds, source,
    timeout). `load_s` holds the bare load times. `speech_s` is how long the
    simulated user spoke before formatting started in the race scenario.
    """
    problems: list[str] = []
    # TODO(human): decide what counts as unacceptable for a dictation.
    return problems


def _summary(label: str, values: list[float]) -> str:
    if not values:
        return f"{label:<6} —"
    return (
        f"{label:<6} n={len(values)}  min {min(values):5.2f}s  "
        f"median {statistics.median(values):5.2f}s  max {max(values):5.2f}s"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--host", default=DEFAULT_HOST, help="Ollama base URL (the private copy is :11435)")
    parser.add_argument("--runs", type=int, default=3, help="repetitions per scenario and language")
    parser.add_argument("--speech", type=float, default=3.0, help="seconds spoken before formatting, race scenario")
    args = parser.parse_args()

    print(f"{fmt.DEFAULT_MODEL} on {args.host}, {args.runs} runs, {args.speech:g}s of speech\n")
    load_s = [time_load(args.host) for _ in range(args.runs)]
    runs: list[Run] = []
    for _ in range(args.runs):
        for lang, text in SAMPLES:
            runs.append(run_cold(lang, text, args.host))
            runs.append(run_race(lang, text, args.host, args.speech))
            runs.append(run_warm(lang, text, args.host))

    for run in runs:
        flag = "" if run.source == "llm" else f"   <- {run.source}"
        print(f"  {run.scenario:<5} {run.lang}  {run.seconds:5.2f}s  (timeout {run.timeout:4.1f}s){flag}")
    print()
    print(_summary("load", load_s))
    for scenario in ("cold", "race", "warm"):
        print(_summary(scenario, [r.seconds for r in runs if r.scenario == scenario]))

    problems = verdict(runs, load_s, args.speech)
    print()
    for line in problems:
        print(f"FAIL  {line}")
    print("FAIL" if problems else "PASS")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
