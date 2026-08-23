"""
Meeting-note summarization for UltraWhisper.

Stdlib only, matching the backend's existing dependency budget (`websockets`
and `numpy`, nothing else). The LLM runs out-of-process in Ollama and is
reached over localhost HTTP with `urllib`.

`contracts` holds the shapes every other module here is written against; see
its docstring before changing anything in it.
"""

from .chunker import (
    DEFAULT_OVERLAP_RATIO,
    DEFAULT_WINDOW_BUDGET_CHARS,
    chunk_transcript,
)
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
from .llm import OllamaStatus, chat_json, probe
from .pipeline import (
    MAX_REDUCE_FACTS,
    STAGE_CLASSIFY,
    STAGE_MAP,
    STAGE_REDUCE,
    STAGE_RENDER,
    SummaryResult,
    summarize_meeting,
)
from .render import render_note, render_note_lines
from .schema import parse_facts, parse_note
from .templates import DEFAULT_MEETING_TYPE, MeetingTemplate, get_template, note_schema_for

__all__ = [
    "BULLET_PREFIX",
    "CHECKBOX_PREFIX",
    "DEFAULT_MEETING_TYPE",
    "DEFAULT_OVERLAP_RATIO",
    "DEFAULT_WINDOW_BUDGET_CHARS",
    "FACTS_JSON_SCHEMA",
    "HEADER_PREFIX",
    "INDENT",
    "MAX_NEST_DEPTH",
    "MAX_REDUCE_FACTS",
    "SPEAKER_LABELS",
    "STAGE_CLASSIFY",
    "STAGE_MAP",
    "STAGE_REDUCE",
    "STAGE_RENDER",
    "Fact",
    "MeetingNote",
    "MeetingTemplate",
    "NoteItem",
    "NoteSection",
    "OllamaStatus",
    "SectionStyle",
    "Segment",
    "Speaker",
    "SummaryResult",
    "TranscriptWindow",
    "Unavailable",
    "chat_json",
    "chunk_transcript",
    "format_timestamp",
    "get_template",
    "note_json_schema",
    "note_schema_for",
    "parse_facts",
    "parse_note",
    "probe",
    "render_note",
    "render_note_lines",
    "render_segment",
    "render_window",
    "summarize_meeting",
]
