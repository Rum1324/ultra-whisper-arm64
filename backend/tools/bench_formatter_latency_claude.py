#!/usr/bin/env python3
"""
Time the dictation-formatting prompt on Claude API models, for comparison with
bench_formatter_latency.py (gemma4:e4b on Ollama). Same SAMPLES, same system
prompt and few-shot turns, same `rejection_reason` gate on the output.

A benchmark, not the product's Claude path (that is backend/claude_client.py).
It sends only the synthetic SAMPLES and the prompt. Needs the SDK and a key in
ANTHROPIC_API_KEY, e.g. from the Keychain:

    ANTHROPIC_API_KEY="$(security find-generic-password -s anthropic-ultrawhisper -w)" \\
    PYTHONPATH=backend backend/python_bundle/python/bin/python3 \\
        backend/tools/bench_formatter_latency_claude.py [--runs N]

There is no model load to wait for, so "first" here is the first request on a
fresh client: TLS and connection setup, the API's equivalent of a cold start.
Server-side fallbacks are deliberately off: a request rescued by another model
would be timed as the model that refused. A refusal is reported, not hidden.
"""
import argparse
import statistics
import sys
import time

import anthropic

import dictation_formatter as fmt
from bench_formatter_latency import SAMPLES

# $ per million tokens (input, output), platform pricing page as of 2026-10-08.
PRICES = {"haiku": (0.10, 0.50), "sonnet": (2.0, 10.0), "opus": (4.0, 20.0)}

# Lowest-latency thinking setting each model accepts. Opus 5.5 cannot turn
# thinking off, so it runs at low effort; Sonnet 5.5 turns it off with
# between_tools; Haiku is sent neither and runs at its default.
EXTRA = {
    "sonnet": {"thinking": {"type": "between_tools"}},
    "opus": {"output_config": {"effort": "low"}},
    "haiku": {},
}


def resolve_models(client: anthropic.Anthropic) -> dict[str, str]:
    """Map family -> model id from the Models API rather than guessing ids."""
    wanted = {"haiku": "Haiku 5.5", "sonnet": "Sonnet 5.5", "opus": "Opus 5.5"}
    found = {}
    for model in client.models.list():
        for family, name in wanted.items():
            if name in model.display_name and family not in found:
                found[family] = model.id
    missing = set(wanted) - set(found)
    if missing:
        sys.exit(f"Models API did not list: {', '.join(wanted[m] for m in sorted(missing))}")
    return found


def call(client: anthropic.Anthropic, family: str, model: str, text: str):
    messages = fmt.build_messages(text)
    start = time.monotonic()
    response = client.messages.create(
        model=model,
        max_tokens=2048,
        system=messages[0]["content"],
        messages=messages[1:],
        **EXTRA[family],
    )
    seconds = time.monotonic() - start
    if response.stop_reason == "refusal":
        return seconds, "refusal", "", response.usage
    output = "".join(b.text for b in response.content if b.type == "text")
    output = fmt._TAG_RE.sub("", output).strip()
    reason = fmt.rejection_reason(text, output)
    return seconds, f"rejected: {reason}" if reason else "ok", output, response.usage


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--runs", type=int, default=3, help="repetitions per model and language")
    args = parser.parse_args()

    models = resolve_models(anthropic.Anthropic())
    total_cost = 0.0
    for family, model in models.items():
        client = anthropic.Anthropic()  # fresh client: the first call pays connection setup
        first: float | None = None
        later: list[float] = []
        print(f"\n{model}")
        for _ in range(args.runs):
            for lang, text in SAMPLES:
                seconds, verdict, output, usage = call(client, family, model, text)
                price_in, price_out = PRICES[family]
                cost = (usage.input_tokens * price_in + usage.output_tokens * price_out) / 1e6
                total_cost += cost
                if first is None:
                    first = seconds
                else:
                    later.append(seconds)
                flag = "" if verdict == "ok" else f"   <- {verdict}"
                print(f"  {lang}  {seconds:5.2f}s  in {usage.input_tokens:4d}  out {usage.output_tokens:4d}{flag}")
                print(f"      {output[:100]}")
        print(f"  first {first:.2f}s   then median {statistics.median(later):.2f}s  max {max(later):.2f}s")
    print(f"\ntotal spend ${total_cost:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
