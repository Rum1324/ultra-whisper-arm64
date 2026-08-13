"""
Meeting-note summarization for UltraWhisper.

Stdlib only, matching the backend's existing dependency budget (`websockets`
and `numpy`, nothing else). The LLM runs out-of-process in Ollama and is
reached over localhost HTTP with `urllib`.

`contracts` holds the shapes every other module here is written against; see
its docstring before changing anything in it.
"""

from .contracts import (
    BULLET_PREFIX,
    CHECKBOX_PREFIX,
    FACTS_JSON_SCHEMA,
    HEADER_PREFIX,
    INDENT,
    MAX_NEST_DEPTH,
    SPEAKER_LABELS,
    Fact,
    MeetingNote,
    NoteItem,
    NoteSection,
    SectionStyle,
    Segment,
    Speaker,
    TranscriptWindow,
    Unavailable,
    format_timestamp,
    note_json_schema,
    render_segment,
    render_window,
)

__all__ = [
    "BULLET_PREFIX",
    "CHECKBOX_PREFIX",
    "FACTS_JSON_SCHEMA",
    "HEADER_PREFIX",
    "INDENT",
    "MAX_NEST_DEPTH",
    "SPEAKER_LABELS",
    "Fact",
    "MeetingNote",
    "NoteItem",
    "NoteSection",
    "SectionStyle",
    "Segment",
    "Speaker",
    "TranscriptWindow",
    "Unavailable",
    "format_timestamp",
    "note_json_schema",
    "render_segment",
    "render_window",
]
