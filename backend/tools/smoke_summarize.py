#!/usr/bin/env python3
"""
Run the meeting-notes pipeline against a live Ollama and print the note.

Exists because the summarize path cannot be covered by the unit tests — those
stub the model — so the only way to know a given Ollama tag produces a USABLE
note is to give it a transcript with known content and read what comes back.

    PYTHONPATH=backend python3 backend/tools/smoke_summarize.py <ollama-tag>

The fixture below deliberately contains one decision, one owned action item
with a deadline, and one date. A note that misses them is a weak note no matter
how fluent it reads; that is the bar, not whether it returns something.
"""
import sys
import time

from summarize.contracts import Segment, Unavailable
from summarize.pipeline import summarize_meeting

LINES = [
    ("me", "Thanks for jumping on. I wanted to close out the pricing question."),
    ("them", "Right. We looked at the numbers and the annual plan is the problem."),
    ("me", "Problem how?"),
    ("them", "Churn spikes at renewal because nobody remembers signing up."),
    ("me", "So we move to monthly by default and keep annual as an option?"),
    ("them", "That's my recommendation, yes."),
    ("me", "Agreed, let's do that. Can you write it up before Friday?"),
    ("them", "I'll have the pricing doc ready by Thursday and send it over."),
    ("me", "Perfect. I'll tell the board on the 3rd of September."),
]

# What a competent note must surface, for eyeballing the output against.
EXPECTED = [
    "decision: default to monthly billing",
    "action: them writes the pricing doc, due Thursday",
    "date: board update on 3 September",
]


def main() -> int:
    model = sys.argv[1] if len(sys.argv) > 1 else "hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q3_K_XL"
    segments = [
        Segment(t0=float(i * 8), t1=float(i * 8 + 7), speaker=speaker, text=text)
        for i, (speaker, text) in enumerate(LINES)
    ]

    print(f"model: {model}")
    started = time.time()
    result = summarize_meeting(
        segments,
        model=model,
        title="Pricing sync",
        progress=lambda stage, done, total: print(f"  [{stage}] {done}/{total}"),
    )
    elapsed = time.time() - started

    if isinstance(result, Unavailable):
        print(f"\nUNAVAILABLE  reason={result.reason}\n  {result.detail}")
        if result.remedy:
            print(f"  remedy: {result.remedy}")
        return 1

    print(f"\nOK in {elapsed:.1f}s   type={result.meeting_type}")
    print(f"sections: {[s.title for s in result.note.sections]}")
    print("\n--- markdown ---")
    print(result.markdown)
    print("\n--- should mention ---")
    for item in EXPECTED:
        print(f"  - {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
