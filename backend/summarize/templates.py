#!/usr/bin/env python3
"""
Per-meeting-type section menus.

A template carries two things that look similar and are not:

* `suggested_titles` is a HINT. It is handed to `contracts.note_json_schema`
  as prose in the schema description, never as an enum — see that function's
  docstring for why. The model stays free to invent a better title, and this
  module must never treat an off-menu title as an error.
* `checkbox_titles` is a DECISION. contracts.py states that bullet style is
  chosen per-section by the template rather than per-item by the model, so
  this is the authority `schema.py` falls back to when the model omits
  `style` — which the Phase 0 smoke test says is the normal case, not the
  exception.

Because titles are free text, an exact-match table can only ever cover the
menu. `MeetingTemplate.style_for` therefore falls through to a keyword match,
so an invented "Action Items For Me" or "次のステップ" still renders as
checkboxes instead of silently degrading to bullets.
"""

import re
from dataclasses import dataclass
from typing import Any, Optional

from .contracts import SectionStyle, note_json_schema

DEFAULT_MEETING_TYPE = "generic"

# Meeting-type keys are compared after squashing every run of non-alphanumerics
# to a single underscore, so "One-on-One", "one on one" and "1:1" all land on
# the same lookup key without needing an entry each.
_TYPE_NOISE_RE = re.compile(r"[^a-z0-9]+")

# Section titles are normalized far more gently: only separators are folded and
# decorative edge punctuation trimmed. Stripping non-ASCII the way the meeting
# -type key does would collapse every Japanese title to the empty string and
# make them all compare equal.
_TITLE_SEPARATOR_RE = re.compile(r"[\s_\-‐-―]+")
_TITLE_EDGE_CHARS = " :.!?*#>-：。！？"

# Titles that mean "things somebody committed to do", however the model chose to
# phrase them. Word-bounded so "Transaction Volume" does not become a checklist.
_CHECKBOX_WORD_RE = re.compile(
    r"\b(?:action items?|actions?|to ?dos?|next steps?|follow[ -]?ups?"
    r"|tasks?|commitments?|homework|deliverables?)\b"
)

# The app is EN/JA, and Japanese has no word boundaries to anchor against, so
# these are matched as plain substrings.
_CHECKBOX_SUBSTRINGS = ("アクション", "タスク", "次のステップ", "宿題", "todo")


def normalize_meeting_type(meeting_type: Any) -> str:
    """Fold a caller-supplied meeting type onto its lookup key."""
    if not isinstance(meeting_type, str):
        return ""
    return _TYPE_NOISE_RE.sub("_", meeting_type.strip().lower()).strip("_")


def normalize_title(title: Any) -> str:
    """Fold a section title for comparison, preserving non-Latin scripts."""
    if not isinstance(title, str):
        return ""
    folded = _TITLE_SEPARATOR_RE.sub(" ", title.casefold())
    return folded.strip(_TITLE_EDGE_CHARS).strip()


@dataclass(frozen=True, slots=True)
class MeetingTemplate:
    """The per-meeting-type knowledge the note pipeline needs."""

    meeting_type: str
    suggested_titles: tuple[str, ...] = ()
    checkbox_titles: tuple[str, ...] = ()

    def style_for(self, title: Any) -> SectionStyle:
        """
        Decide how a section's items should be marked.

        Exact menu match first, then a keyword fallback for titles the model
        invented. Anything unrecognised is a bullet: a plain observation
        rendered as an unchecked box reads as an unmet commitment, which is a
        worse failure than an action item rendered as a bullet.
        """
        key = normalize_title(title)
        if not key:
            return "bullet"
        if any(key == normalize_title(t) for t in self.checkbox_titles):
            return "checkbox"
        if _CHECKBOX_WORD_RE.search(key):
            return "checkbox"
        if any(needle in key for needle in _CHECKBOX_SUBSTRINGS):
            return "checkbox"
        return "bullet"


GENERIC_TEMPLATE = MeetingTemplate(
    meeting_type="generic",
    suggested_titles=("Summary", "Key Points", "Decisions", "Open Questions", "Action Items"),
    checkbox_titles=("Action Items",),
)

TEMPLATES: dict[str, MeetingTemplate] = {
    "coffee_chat": MeetingTemplate(
        meeting_type="coffee_chat",
        suggested_titles=(
            "Who They Are",
            "What We Talked About",
            "Interesting Threads",
            "People and Places Mentioned",
            "Follow-Ups",
        ),
        checkbox_titles=("Follow-Ups",),
    ),
    "one_on_one": MeetingTemplate(
        meeting_type="one_on_one",
        suggested_titles=(
            "Updates",
            "Blockers",
            "Feedback",
            "Career and Growth",
            "Action Items",
        ),
        checkbox_titles=("Action Items",),
    ),
    "standup": MeetingTemplate(
        meeting_type="standup",
        suggested_titles=("Since Last Time", "Today", "Blockers", "Action Items"),
        checkbox_titles=("Action Items", "Blockers"),
    ),
    "interview": MeetingTemplate(
        meeting_type="interview",
        suggested_titles=(
            "Candidate Background",
            "Signals",
            "Concerns",
            "Questions They Asked",
            "Next Steps",
        ),
        checkbox_titles=("Next Steps",),
    ),
    "customer_call": MeetingTemplate(
        meeting_type="customer_call",
        suggested_titles=(
            "Their Situation",
            "Pain Points",
            "Feature Requests",
            "Objections",
            "Next Steps",
        ),
        checkbox_titles=("Next Steps",),
    ),
    "generic": GENERIC_TEMPLATE,
}

# Spellings a caller or a UI picker might plausibly send, mapped onto the
# canonical key. Anything not listed still falls back to `generic` rather than
# raising, so an unknown type degrades to a usable note.
_ALIASES: dict[str, str] = {
    "1_1": "one_on_one",
    "1_on_1": "one_on_one",
    "11": "one_on_one",
    "1on1": "one_on_one",
    "one_one": "one_on_one",
    "oneonone": "one_on_one",
    "check_in": "one_on_one",
    "coffee": "coffee_chat",
    "chat": "coffee_chat",
    "intro_call": "coffee_chat",
    "daily": "standup",
    "daily_standup": "standup",
    "stand_up": "standup",
    "scrum": "standup",
    "candidate_interview": "interview",
    "screen": "interview",
    "customer": "customer_call",
    "sales_call": "customer_call",
    "discovery_call": "customer_call",
    "user_interview": "customer_call",
    "": "generic",
    "default": "generic",
    "meeting": "generic",
    "other": "generic",
}


def get_template(meeting_type: Any = DEFAULT_MEETING_TYPE) -> MeetingTemplate:
    """Look up a template, falling back to `generic` for anything unknown."""
    key = normalize_meeting_type(meeting_type)
    key = _ALIASES.get(key, key)
    return TEMPLATES.get(key, GENERIC_TEMPLATE)


def suggested_titles_for(meeting_type: Any = DEFAULT_MEETING_TYPE) -> tuple[str, ...]:
    """The title menu to hint at in the schema for this meeting type."""
    return get_template(meeting_type).suggested_titles


def style_for_title(
    title: Any,
    *,
    meeting_type: Any = DEFAULT_MEETING_TYPE,
    template: Optional[MeetingTemplate] = None,
) -> SectionStyle:
    """Convenience wrapper used by `schema.py` when the model omits `style`."""
    resolved = template if template is not None else get_template(meeting_type)
    return resolved.style_for(title)


def note_schema_for(
    meeting_type: Any = DEFAULT_MEETING_TYPE,
    *,
    max_sections: int = 8,
) -> dict[str, Any]:
    """Build the reduce-pass schema with this meeting type's titles as a hint."""
    return note_json_schema(
        suggested_titles=suggested_titles_for(meeting_type),
        max_sections=max_sections,
    )
