#!/usr/bin/env python3
"""
Tolerant parsing of model output into the `contracts.py` dataclasses.

Nothing here raises. A local 2B-class model asked for JSON will hand back
something schema-shaped most of the time and something schema-adjacent the
rest of the time, and the note is an enhancement on top of a transcript that
already works — degrading to a thinner note beats surfacing a stack trace.

The deviations handled below are not hypothetical; they are what the Phase 0
smoke test and the schema's own `required` list predict:

* Items arrive as bare strings instead of `{"text": ...}`. Extremely common.
* `style` is missing. This is the NORMAL case — it is deliberately absent from
  the schema's `required` (see `note_json_schema`), so the template decides.
* Containers arrive as null, as a scalar, or as a single object where an array
  was specified.
* Values arrive with the wrong type: numbers, nested dicts, `None`.

Text is only type-coerced and outer-stripped here. Collapsing newlines and
stripping leaked markdown belongs to `render.py`, which has to guarantee those
properties for hand-built notes too, not just parsed ones.
"""

import json
import math
import re
from typing import Any, Optional

from .contracts import Fact, MeetingNote, NoteItem, NoteSection, SectionStyle, Speaker
from .templates import DEFAULT_MEETING_TYPE, MeetingTemplate, get_template

# Recursion cap for `children`. The renderer flattens everything past depth 1
# anyway, so nothing a real model emits is lost here; the cap exists so a
# pathological (or hand-built, self-referential) structure cannot exhaust the
# stack inside a function that promises never to raise.
_MAX_PARSE_DEPTH = 8

# Total NoteItems one parse may build, across the whole tree. Depth alone does
# not bound the work when the payload shares references (see _coerce_items);
# this does, unconditionally. Far above any real note — a model producing 20k
# bullet points has already failed in a way a cap will not rescue.
_MAX_PARSE_NODES = 20_000

_VALID_STYLES: frozenset[str] = frozenset(("bullet", "checkbox"))
_VALID_SPEAKERS: frozenset[str] = frozenset(("me", "them"))

# Fences around JSON are a model habit, not a schema feature, and llm.py may or
# may not have stripped them before we see the payload.
#
# Deliberately NOT a regex. The obvious pattern here is
#     r"^\s*```(?:json)?\s*(.*?)\s*```\s*$"
# and it backtracks cubically when the closing fence is absent: the two
# unbounded \s* runs either side of the lazy (.*?) each offer O(n) split points.
# An adversarial pass measured 0.036s at 307 characters growing to 17.3s at
# 2407 — roughly 8x per doubling — so a 20k-character payload takes hours.
# That input is not exotic: it is exactly what a model emits when it opens a
# fence and then hits its token limit. String scanning is O(n) and cannot
# backtrack.
_JSON_FENCE = "```"
_JSON_FENCE_TAG = "json"


def _strip_json_fence(payload: str) -> str:
    """Unwrap ```json ... ``` if both fences are present, else leave it alone."""
    stripped = payload.strip()
    if not stripped.startswith(_JSON_FENCE):
        return payload
    if len(stripped) < 2 * len(_JSON_FENCE) or not stripped.endswith(_JSON_FENCE):
        # Unterminated fence. There is nothing well-formed to unwrap, and
        # guessing at where the body ends would only feed json.loads garbage.
        return payload
    body = stripped[len(_JSON_FENCE) : -len(_JSON_FENCE)].lstrip()
    if body[: len(_JSON_FENCE_TAG)].lower() == _JSON_FENCE_TAG:
        body = body[len(_JSON_FENCE_TAG) :]
    return body.strip()

# `t0` sometimes comes back as the literal "[00:12:34]" copied out of the
# prompt rather than as the number of seconds the schema asked for.
_TIMESTAMP_RE = re.compile(r"^\[?\s*(\d{1,3}):([0-5]?\d)(?::([0-5]?\d))?\s*\]?$")

_SPEAKER_ALIASES: dict[str, Speaker] = {
    "me": "me",
    "i": "me",
    "self": "me",
    "user": "me",
    "mic": "me",
    "speaker 1": "me",
    "them": "them",
    "they": "them",
    "other": "them",
    "guest": "them",
    "system": "them",
    "speaker 2": "them",
}


def _decode(payload: Any) -> Any:
    """Best-effort JSON decode, so a raw model string is as welcome as a dict."""
    if not isinstance(payload, (str, bytes, bytearray)):
        return payload
    if isinstance(payload, (bytes, bytearray)):
        try:
            payload = payload.decode("utf-8", errors="replace")
        except Exception:
            return None
    payload = _strip_json_fence(payload)
    try:
        return json.loads(payload)
    except Exception:
        return None


def _coerce_text(value: Any) -> str:
    """
    Turn whatever landed in a text field into a string, or into nothing.

    Booleans are rejected before the numeric branch: `True` is an `int`
    subclass, and an item reading "True" is noise rather than content.
    """
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, bool) or value is None:
        return ""
    if isinstance(value, (int, float)):
        if isinstance(value, float) and not math.isfinite(value):
            return ""
        try:
            return str(value).strip()
        except Exception:
            # str() of an int is not total: CPython caps int->str conversion at
            # 4300 digits and raises ValueError past it. This module promises
            # never to raise, so an absurd number becomes no content.
            return ""
    return ""


def _coerce_style(value: Any) -> Optional[SectionStyle]:
    """Return a valid style, or None to mean "let the template decide"."""
    if isinstance(value, str):
        candidate = value.strip().lower()
        if candidate in _VALID_STYLES:
            return candidate  # type: ignore[return-value]
    return None


def _coerce_item(value: Any, depth: int, budget: Optional[list] = None) -> Optional[NoteItem]:
    """Build one NoteItem, or None when there is nothing worth keeping."""
    if budget is None:
        budget = [_MAX_PARSE_NODES]
    if budget[0] <= 0:
        return None
    budget[0] -= 1

    if isinstance(value, str) or isinstance(value, (int, float)):
        text = _coerce_text(value)
        return NoteItem(text=text) if text else None

    if isinstance(value, dict):
        text = _coerce_text(value.get("text"))
        children: list[NoteItem] = []
        if depth < _MAX_PARSE_DEPTH:
            children = _coerce_items(value.get("children"), depth + 1, budget)
        if not text and not children:
            return None
        return NoteItem(text=text, children=children)

    return None


def _coerce_items(value: Any, depth: int = 0, budget: Optional[list] = None) -> list[NoteItem]:
    """
    Coerce an `items`/`children` field that may be anything at all.

    `budget` is a one-element list used as a shared mutable counter across the
    whole parse. Depth alone does NOT bound the work: a payload whose children
    list contains the node that owns it materialises fan-out**_MAX_PARSE_DEPTH
    objects, and an adversarial pass reached 6.5e12 (fan-out 40) — parse_note
    never returned and memory climbed without bound. json.loads cannot build
    that sharing, so this is unreachable from a model response, but the
    no-raise/always-returns promise should not quietly depend on who the caller
    is.
    """
    if budget is None:
        budget = [_MAX_PARSE_NODES]
    if value is None or budget[0] <= 0:
        return []
    if isinstance(value, (str, int, float, dict)):
        # A single item where an array was specified.
        single = _coerce_item(value, depth, budget)
        return [single] if single is not None else []
    if not isinstance(value, (list, tuple)):
        return []

    items: list[NoteItem] = []
    for entry in value:
        if budget[0] <= 0:
            break
        item = _coerce_item(entry, depth, budget)
        if item is not None:
            items.append(item)
    return items


def _coerce_section(
    value: Any,
    *,
    template: MeetingTemplate,
    prefer_template_style: bool,
) -> Optional[NoteSection]:
    """Build one NoteSection, resolving style against the template."""
    if isinstance(value, str):
        title = _coerce_text(value)
        if not title:
            return None
        return NoteSection(title=title, style=template.style_for(title), items=[])

    if not isinstance(value, dict):
        return None

    title = _coerce_text(value.get("title"))
    items = _coerce_items(value.get("items"))
    if not title and not items:
        return None

    model_style = _coerce_style(value.get("style"))
    template_style = template.style_for(title)
    if prefer_template_style or model_style is None or template_style == "checkbox":
        # The template wins wherever it has a POSITIVE opinion, because
        # "checkbox" is knowledge (this title names commitments) while "bullet"
        # is merely its default for a title it does not recognise. Neither
        # extreme is right: template-always ignores a model correctly marking a
        # section the keyword list never anticipated, and model-always lets
        # model noise overrule knowledge the template actually has.
        style: SectionStyle = template_style
    else:
        style = model_style

    return NoteSection(title=title, style=style, items=items)


def _coerce_sections(
    value: Any,
    *,
    template: MeetingTemplate,
    prefer_template_style: bool,
) -> list[NoteSection]:
    if value is None:
        return []
    if isinstance(value, dict):
        value = [value]
    if not isinstance(value, (list, tuple)):
        return []

    sections: list[NoteSection] = []
    for entry in value:
        section = _coerce_section(
            entry,
            template=template,
            prefer_template_style=prefer_template_style,
        )
        if section is not None:
            sections.append(section)
    return sections


def parse_note(
    payload: Any,
    *,
    meeting_type: Any = DEFAULT_MEETING_TYPE,
    fallback_title: str = "Meeting Notes",
    prefer_template_style: bool = False,
) -> MeetingNote:
    """
    Build a MeetingNote out of whatever the reduce pass produced.

    `prefer_template_style` decides who wins when the model *did* supply a
    `style`. contracts.py says the template owns the choice; the default here
    is the softer reading — honour an explicit, valid model style and fall back
    to the template otherwise — because a model that bothered to mark a section
    `checkbox` usually had a reason. Callers who want the contract read
    strictly can flip this.

    The returned `meeting_type` is the canonical key the template resolved to,
    not the string the caller passed, so downstream code sees one spelling.
    """
    template = get_template(meeting_type)
    decoded = _decode(payload)

    if isinstance(decoded, (list, tuple)):
        # A bare array of sections, with the wrapper object omitted.
        decoded = {"sections": decoded}
    if not isinstance(decoded, dict):
        decoded = {}

    title = _coerce_text(decoded.get("title")) or fallback_title
    sections = _coerce_sections(
        decoded.get("sections"),
        template=template,
        prefer_template_style=prefer_template_style,
    )
    return MeetingNote(title=title, meeting_type=template.meeting_type, sections=sections)


def _coerce_speaker(value: Any, default: Speaker) -> Speaker:
    if isinstance(value, str):
        candidate = value.strip().lower()
        if candidate in _VALID_SPEAKERS:
            return candidate  # type: ignore[return-value]
        aliased = _SPEAKER_ALIASES.get(candidate)
        if aliased is not None:
            return aliased
    return default


def _coerce_seconds(value: Any) -> float:
    """
    Coerce `t0` to non-negative finite seconds.

    Accepts the `HH:MM:SS`/`MM:SS` stamp as well as a number, because the
    transcript in the prompt is stamped that way and models copy what they see.
    """
    if isinstance(value, bool) or value is None:
        return 0.0
    if isinstance(value, (int, float)):
        try:
            seconds = float(value)
        except Exception:
            # float() of a sufficiently large int raises OverflowError. This
            # module promises never to raise, so an absurd stamp becomes 0.
            return 0.0
        return seconds if math.isfinite(seconds) and seconds > 0 else 0.0
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return 0.0
        stamped = _TIMESTAMP_RE.match(text)
        if stamped:
            first, second, third = stamped.groups()
            if third is None:
                return float(int(first) * 60 + int(second))
            return float(int(first) * 3600 + int(second) * 60 + int(third))
        try:
            seconds = float(text)
        except ValueError:
            return 0.0
        return seconds if math.isfinite(seconds) and seconds > 0 else 0.0
    return 0.0


def parse_facts(payload: Any, *, default_speaker: Speaker = "them") -> list[Fact]:
    """
    Build Facts out of whatever the map pass produced.

    Unattributable lines default to "them" rather than "me": putting words in
    the user's own mouth is the more damaging of the two mistakes, since the
    note is written from their point of view.
    """
    decoded = _decode(payload)

    if isinstance(decoded, dict):
        raw_facts: Any = decoded.get("facts")
    elif isinstance(decoded, (list, tuple)):
        raw_facts = decoded
    else:
        raw_facts = None

    if isinstance(raw_facts, (str, dict)):
        raw_facts = [raw_facts]
    if not isinstance(raw_facts, (list, tuple)):
        return []

    facts: list[Fact] = []
    for entry in raw_facts:
        if isinstance(entry, str):
            text = _coerce_text(entry)
            if text:
                facts.append(Fact(text=text, speaker=default_speaker, t0=0.0))
            continue
        if not isinstance(entry, dict):
            continue
        text = _coerce_text(entry.get("text"))
        if not text:
            continue
        facts.append(
            Fact(
                text=text,
                speaker=_coerce_speaker(entry.get("speaker"), default_speaker),
                t0=_coerce_seconds(entry.get("t0")),
            )
        )
    return facts
