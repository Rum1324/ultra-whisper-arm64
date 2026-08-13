#!/usr/bin/env python3
"""
Frozen shapes shared by every module under `summarize/`.

This file is the Phase 0 contract. `chunker.py`, `llm.py`, `schema.py`,
`render.py` and `pipeline.py` are all written against it independently, so
changing anything here breaks work already in flight. Add fields rather than
renaming them, and treat the render constants at the bottom as load-bearing:
the renderer's guarantee is stated in terms of them, and the tests assert
against them rather than against string literals.

Nothing here parses untrusted model output. Tolerant parsing lives in
`schema.py`, which builds the dataclasses below out of whatever the model
actually emitted.
"""

from dataclasses import dataclass, field
from typing import Any, Literal, Sequence

# ---------------------------------------------------------------------------
# Transcript
# ---------------------------------------------------------------------------

# Which track a segment came from. The two-track capture (mic vs. per-process
# system audio tap) is what makes speaker attribution possible at all — whisper
# does no diarization here, the separation is physical.
Speaker = Literal["me", "them"]

SPEAKER_LABELS: dict[str, str] = {
    "me": "Me",
    "them": "Them",
}


@dataclass(frozen=True, slots=True)
class Segment:
    """
    One whisper segment, stamped with time from the START OF THE MEETING.

    whisper.cpp restarts `t0`/`t1` at zero on every `whisper_full()` call, so a
    meeting transcribed as a series of rolling windows produces many segments
    that each believe they start at 0s. The rolling-transcribe path is
    responsible for adding the window's absolute offset BEFORE constructing a
    Segment. Everything downstream may assume these times are absolute and
    monotonic across the whole meeting.
    """

    t0: float
    t1: float
    speaker: Speaker
    text: str


@dataclass(frozen=True, slots=True)
class TranscriptWindow:
    """A contiguous slice of the meeting handed to the map pass as one unit."""

    index: int
    t0: float
    t1: float
    segments: tuple[Segment, ...]


def format_timestamp(seconds: float) -> str:
    """
    Render absolute seconds as `HH:MM:SS`.

    Zero-padded and always three components, so timestamps sort lexically and
    stay a fixed width in the prompt — a ragged left margin measurably hurts
    the model's ability to attribute facts to the right moment.
    """
    total = max(0, int(seconds))
    hours, remainder = divmod(total, 3600)
    minutes, secs = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


def render_segment(segment: Segment) -> str:
    """Format one segment as `[00:12:34] Me: ...` for the prompt."""
    label = SPEAKER_LABELS.get(segment.speaker, segment.speaker)
    return f"[{format_timestamp(segment.t0)}] {label}: {segment.text}"


def render_window(window: TranscriptWindow) -> str:
    """
    Format a whole window as speaker-labelled lines.

    Prompt-writers beware: labelling the transcript `Me:`/`Them:` is NOT enough
    on its own to make the model carry that attribution into the note. A Phase 0
    smoke test against gemma4:e2b produced "Speaker 1"/"Speaker 2" in every item
    despite a correctly labelled transcript. Since per-owner attribution is the
    entire reason the two-track capture exists, the system prompt has to demand
    it explicitly and the result is worth asserting on.
    """
    return "\n".join(render_segment(s) for s in window.segments)


# ---------------------------------------------------------------------------
# Note
# ---------------------------------------------------------------------------

# How a section's items are bulleted. Chosen per-section by the template, not
# per-item by the model — asking a model to decide "is this a task?" per line
# produces checkbox soup.
SectionStyle = Literal["bullet", "checkbox"]


@dataclass(slots=True)
class NoteItem:
    """
    One line of note content.

    `children` exists because models produce nesting whether or not the schema
    invites it. Depth beyond one level is flattened by the renderer rather than
    rejected — a note that loses its indentation is still useful, a note that
    fails to render is not.
    """

    text: str
    children: list["NoteItem"] = field(default_factory=list)


@dataclass(slots=True)
class NoteSection:
    title: str
    style: SectionStyle = "bullet"
    items: list[NoteItem] = field(default_factory=list)


@dataclass(slots=True)
class MeetingNote:
    title: str
    meeting_type: str
    sections: list[NoteSection] = field(default_factory=list)


@dataclass(frozen=True, slots=True)
class Fact:
    """One atom extracted by the map pass, before reduction into a note."""

    text: str
    speaker: Speaker
    t0: float


# ---------------------------------------------------------------------------
# Render guarantee
# ---------------------------------------------------------------------------

# The renderer promises: every header is exactly these three hashes plus a
# space, every content line begins with one of the two markers below, and
# nothing indents further than INDENT once. The adversarial pass asserts
# against these names so a change here is a change to the promise.
HEADER_PREFIX = "### "
BULLET_PREFIX = "- "
CHECKBOX_PREFIX = "- [ ] "
INDENT = "  "
MAX_NEST_DEPTH = 1


# ---------------------------------------------------------------------------
# JSON Schema handed to the model
# ---------------------------------------------------------------------------


def note_json_schema(
    *,
    suggested_titles: Sequence[str] = (),
    max_sections: int = 8,
) -> dict[str, Any]:
    """
    Build the schema constraining the reduce pass.

    Section titles are deliberately FREE TEXT with the per-meeting-type menu
    passed as a description hint. Making them an enum forces the model to
    invent empty sections purely to satisfy the enum, which is worse than a
    slightly off-menu title: a coffee chat should be free to emit "Their
    Background" without also emitting an empty "Action Items".

    `style` is likewise a hint the renderer may override — the template owns
    which sections are checkbox-style, not the model. It is deliberately absent
    from `required`, and the Phase 0 smoke test confirms models simply omit it,
    so parsing MUST treat a missing `style` as the normal case rather than an
    error, and fall back to the template's choice.
    """
    title_hint = (
        f" Typical titles for this kind of meeting: {', '.join(suggested_titles)}."
        " Use these when they fit, invent a better one when they do not, and"
        " omit any section you have no content for."
        if suggested_titles
        else " Omit any section you have no content for."
    )

    return {
        "type": "object",
        "properties": {
            "title": {
                "type": "string",
                "description": "A short title naming what this meeting was about.",
            },
            "sections": {
                "type": "array",
                "maxItems": max_sections,
                "description": "The note's sections, in reading order." + title_hint,
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {
                            "type": "string",
                            "description": "Plain text only — no markdown, no leading '#'.",
                        },
                        "style": {
                            "type": "string",
                            "enum": ["bullet", "checkbox"],
                            "description": "Use 'checkbox' only for sections of actionable commitments.",
                        },
                        "items": {
                            "type": "array",
                            "description": "One point per entry. Plain text — no leading '-', '*' or '[ ]'.",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "text": {"type": "string"},
                                    "children": {
                                        "type": "array",
                                        "description": "Sub-points. Avoid unless genuinely subordinate.",
                                        "items": {
                                            "type": "object",
                                            "properties": {"text": {"type": "string"}},
                                            "required": ["text"],
                                        },
                                    },
                                },
                                "required": ["text"],
                            },
                        },
                    },
                    "required": ["title", "items"],
                },
            },
        },
        "required": ["title", "sections"],
    }


# Map pass: pull atoms out of one window. Kept far simpler than the note schema
# because it runs once per window and its output is never shown to the user.
FACTS_JSON_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "facts": {
            "type": "array",
            "description": "Everything from this excerpt worth carrying into a note.",
            "items": {
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "One self-contained fact, decision, question or commitment.",
                    },
                    "speaker": {
                        "type": "string",
                        "enum": ["me", "them"],
                        "description": "Who said it, per the transcript labels.",
                    },
                    "t0": {
                        "type": "number",
                        "description": "Seconds from the start of the meeting, from the [HH:MM:SS] stamp.",
                    },
                },
                "required": ["text", "speaker", "t0"],
            },
        }
    },
    "required": ["facts"],
}


# ---------------------------------------------------------------------------
# Summarization availability
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Unavailable:
    """
    Returned by `llm.py` instead of raising when summarization cannot run.

    Meeting notes are an enhancement layered on a transcript that already
    works. Ollama being absent, or the model not being pulled, must never cost
    the user their transcript — so this is an ordinary return value that
    `pipeline.py` forwards to the UI, not an exception.

    `remedy` is a shell command safe to show the user verbatim.
    """

    reason: Literal["no_server", "no_model", "timeout", "bad_response"]
    detail: str
    remedy: str | None = None
