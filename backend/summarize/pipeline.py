#!/usr/bin/env python3
"""
The classify → map → reduce → render run behind the `summarize` command.

This is the module `llm.py` names when it promises that every failure "comes
back as `contracts.Unavailable`". Everything below inherits that promise:
`summarize_meeting` does not raise, and callers in `server.py` may forward its
`Unavailable` straight out as a `summary_unavailable` event.

Why four passes rather than one prompt:

* An hour of meeting does not fit in a small model's context, and Ollama
  silently truncates an over-long prompt rather than erroring (see
  `llm.chat_json`). A single-shot summary of a long meeting therefore fails by
  quietly forgetting its first half — the worst possible failure mode, because
  the note still looks fine.
* The map pass extracts *facts* rather than prose. Facts survive being
  concatenated across windows; prose summaries do not, because summarising a
  pile of summaries compounds each one's omissions.

Not every pass is load-bearing, and they fail differently on purpose:

* `classify` is an OPTIMIZATION. It only picks which section menu to suggest,
  so when it fails the run continues against the generic template. Losing the
  ideal set of headings is not worth losing the note.
* `map` is TOLERANT of individual windows. One window that trips a model bug
  costs its own facts and nothing else; only when every window fails does the
  run give up and return the first failure it saw.
* `reduce` is REQUIRED. There is no note without it, so its `Unavailable`
  propagates unchanged.

Both prompts demand `Me`/`Them` attribution in as many words. That is not
stylistic: the smoke test recorded in `contracts.render_window` produced
"Speaker 1"/"Speaker 2" throughout despite a correctly labelled transcript, and
per-owner attribution is the entire reason the capture layer keeps two tracks.
"""

import logging
from dataclasses import dataclass
from typing import Any, Callable, Mapping, Optional, Sequence

from .chunker import DEFAULT_WINDOW_BUDGET_CHARS, chunk_transcript
from .contracts import (
    FACTS_JSON_SCHEMA,
    SPEAKER_LABELS,
    Fact,
    MeetingNote,
    Segment,
    Unavailable,
    format_timestamp,
    render_window,
)
from .llm import unload as unload_model
from .llm import DEFAULT_HOST, chat_json, probe
from .render import render_note
from .schema import parse_facts, parse_note
from .templates import (
    DEFAULT_MEETING_TYPE,
    TEMPLATES,
    get_template,
    normalize_meeting_type,
    note_schema_for,
)

_LOG = logging.getLogger(__name__)

# Progress stages, matching the `summary_progress` event's `stage` field in
# docs/MEETING_PROTOCOL.md. That document is frozen, so these strings are a
# wire contract rather than log text.
STAGE_CLASSIFY = "classify"
STAGE_MAP = "map"
STAGE_REDUCE = "reduce"
STAGE_RENDER = "render"

# `llm.DEFAULT_TIMEOUT_SECONDS` (300) is sized for the reduce pass, whose
# docstring invites the caller to narrow it "when it knows the pass is small".
# These two passes are small, and a map window that has hung is better caught
# in two minutes than in five.
CLASSIFY_TIMEOUT_SECONDS = 60.0
MAP_TIMEOUT_SECONDS = 120.0

# Rough chars-per-token for context sizing. Deliberately pessimistic: Japanese
# transcripts run far denser per character than English, and over-reserving
# context costs a little memory while under-reserving costs the silent
# truncation described above.
_CHARS_PER_TOKEN = 3.0

# Context floor and ceiling for the reduce pass. The floor is Ollama's usual
# default (below which we would be shrinking the window rather than growing
# it); the ceiling keeps a pathological transcript from asking for a context
# no local model can allocate.
_MIN_NUM_CTX = 4096
_MAX_NUM_CTX = 32768

# Facts carried into the reduce prompt. An hour of dense conversation can yield
# hundreds; past this point the prompt stops fitting any local model. Truncation
# here is REPORTED, never silent — see `_facts_prompt`.
MAX_REDUCE_FACTS = 400

ProgressFn = Callable[[str, int, int], None]


@dataclass(frozen=True, slots=True)
class SummaryResult:
    """
    A finished note, in both the forms `summary_final` carries.

    `markdown` is the deliverable the UI shows; `note` is the structure behind
    it, kept so the UI can offer per-section actions later without re-parsing
    markdown. `meeting_type` is echoed because `classify` may have chosen it,
    in which case the caller never saw the value that shaped the note.
    """

    note: MeetingNote
    markdown: str
    meeting_type: str
    model: str
    facts_used: int = 0
    windows_total: int = 0
    windows_failed: int = 0


# The one place an enum is the right call. `contracts.note_json_schema` argues
# at length against constraining section *titles* to a menu — but a meeting type
# is not a title, it is a lookup key into `TEMPLATES`, and a value outside that
# table can only degrade to generic. Letting the model invent one would trade a
# free-text title's upside for none at all.
def _classify_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "properties": {
            "meetingType": {
                "type": "string",
                "enum": sorted(TEMPLATES),
                "description": "The kind of meeting this transcript is.",
            }
        },
        "required": ["meetingType"],
    }


_CLASSIFY_SYSTEM = (
    "You label meeting transcripts by kind. Answer with one of the allowed "
    "values and nothing else. The transcript is labelled 'Me' for the person "
    "recording and 'Them' for everyone else."
)

_MAP_SYSTEM = (
    "You extract facts from a meeting transcript excerpt.\n"
    "Return every fact, decision, question and commitment worth carrying into "
    "meeting notes. Each fact must stand on its own without the transcript "
    "next to it — resolve pronouns to what they refer to.\n"
    "Attribute each fact with the speaker label the transcript uses: 'me' for "
    "the person recording, 'them' for the other party. Never invent labels "
    "like 'Speaker 1'. Getting this wrong makes the notes useless.\n"
    "Use the [HH:MM:SS] stamp on the line a fact came from as its t0.\n"
    "Do not summarise, editorialise, or add anything that was not said."
)

_REDUCE_SYSTEM = (
    "You write meeting notes from a timestamped list of facts.\n"
    "Group the facts into sections and write each item as a short, concrete "
    "line. Preserve who said or committed to what: 'me' is the person "
    "recording, 'them' is the other party. Write those as 'I'/'me' and by "
    "role or name for the other party — never as 'Speaker 1' or 'Speaker 2'.\n"
    "Omit any section you have no content for. Never invent facts, and never "
    "pad a thin meeting into a long note.\n"
    "Write in the language the meeting was conducted in."
)


def _notify(progress: Optional[ProgressFn], stage: str, completed: int, total: int) -> None:
    """
    Report progress without letting a bad callback take down the run.

    The callback reaches into `server.py`'s event loop from a worker thread, so
    it is the most likely thing here to raise for reasons that have nothing to
    do with summarization — a closed WebSocket, most obviously. A note that has
    already cost the user minutes of compute must not be lost to that.
    """
    if progress is None:
        return
    try:
        progress(stage, completed, total)
    except Exception:  # noqa: BLE001 - see docstring
        _LOG.warning("progress callback failed at %s %d/%d", stage, completed, total, exc_info=True)


def _num_ctx_for(prompt_chars: int) -> int:
    """Pick a context window big enough that Ollama will not truncate silently."""
    estimated = int(prompt_chars / _CHARS_PER_TOKEN)
    # Headroom for the system prompt, the schema, and the note being generated.
    wanted = estimated * 2 + 1024
    return max(_MIN_NUM_CTX, min(_MAX_NUM_CTX, wanted))


def _render_fact(fact: Fact) -> str:
    label = SPEAKER_LABELS.get(fact.speaker, fact.speaker)
    return f"[{format_timestamp(fact.t0)}] {label}: {fact.text}"


def _facts_prompt(facts: Sequence[Fact]) -> str:
    """Render facts for the reduce pass, reporting any truncation."""
    kept = facts
    if len(facts) > MAX_REDUCE_FACTS:
        # Keep the earliest facts: they carry the meeting's framing, and the
        # chunker's overlap means late windows restate more than early ones do.
        kept = facts[:MAX_REDUCE_FACTS]
        _LOG.warning(
            "reduce prompt truncated to %d of %d facts; the note will not "
            "reflect the tail of the meeting",
            MAX_REDUCE_FACTS,
            len(facts),
        )
    return "\n".join(_render_fact(f) for f in kept)


def _classify(
    *,
    windows: Sequence[Any],
    model: str,
    host: str,
) -> str:
    """
    Guess the meeting type from the opening of the transcript.

    Only the first window is shown. What kind of meeting this is becomes clear
    in the first minutes, and paying for the whole transcript here would cost
    more than the section menu it buys.

    Never fails the run: any `Unavailable`, and any answer outside `TEMPLATES`,
    falls through to the generic template.
    """
    if not windows:
        return DEFAULT_MEETING_TYPE

    answer = chat_json(
        model=model,
        system=_CLASSIFY_SYSTEM,
        user="Which kind of meeting is this?\n\n" + render_window(windows[0]),
        schema=_classify_schema(),
        host=host,
        timeout=CLASSIFY_TIMEOUT_SECONDS,
    )
    if isinstance(answer, Unavailable):
        _LOG.info("classify unavailable (%s); using %s", answer.reason, DEFAULT_MEETING_TYPE)
        return DEFAULT_MEETING_TYPE

    guessed = normalize_meeting_type(answer.get("meetingType") if isinstance(answer, Mapping) else None)
    if guessed in TEMPLATES:
        return guessed

    _LOG.info("classify returned unknown type %r; using %s", guessed, DEFAULT_MEETING_TYPE)
    return DEFAULT_MEETING_TYPE


def summarize_meeting(
    segments: Sequence[Segment],
    *,
    model: str,
    meeting_type: Any = None,
    title: Optional[str] = None,
    host: str = DEFAULT_HOST,
    progress: Optional[ProgressFn] = None,
    budget_chars: int = DEFAULT_WINDOW_BUDGET_CHARS,
    unload_after: bool = True,
) -> "SummaryResult | Unavailable":
    """
    Turn a meeting transcript into a rendered note.

    `unload_after` evicts the model from Ollama when the note is done. On by
    default because a note model large enough to be worth using is large enough
    to matter: Ollama otherwise keeps it resident for its `keep_alive`, and the
    user gets a machine under memory pressure for five minutes after the note
    is already on screen. Pass False when summarising repeatedly in a batch.

    `segments` must carry absolute meeting-relative timestamps; see
    `contracts.Segment` for why that is the caller's job.

    `meeting_type` of `None` — or anything not in `TEMPLATES` — triggers the
    classify pass. Passing a known type skips it, which is what `start_meeting`
    supplying a calendar-derived type is for.

    Returns `SummaryResult`, or `Unavailable` when Ollama cannot produce a note.
    Does not raise.
    """
    # Only evict a model we actually caused to load. An empty transcript and a
    # model that is not pulled both return without generating anything, and
    # unloading in those cases would put a request on the wire that the tests
    # — rightly — assert never happens.
    loaded: list[bool] = []
    try:
        return _summarize(
            segments,
            model=model,
            meeting_type=meeting_type,
            title=title,
            host=host,
            progress=progress,
            budget_chars=budget_chars,
            loaded=loaded,
        )
    finally:
        # try/finally rather than a call before each return: this function has
        # several exit paths and a new one is an easy thing to add without
        # noticing it leaves the weights resident until keep_alive expires.
        if unload_after and loaded:
            unload_model(model=model, host=host)


def _summarize(
    segments: Sequence[Segment],
    *,
    model: str,
    meeting_type: Any = None,
    title: Optional[str] = None,
    host: str = DEFAULT_HOST,
    progress: Optional[ProgressFn] = None,
    budget_chars: int = DEFAULT_WINDOW_BUDGET_CHARS,
    loaded: list[bool],
) -> "SummaryResult | Unavailable":
    """
    The pipeline itself. See `summarize_meeting` for the contract.

    Appends to `loaded` once a request has been made that causes Ollama to hold
    the model in memory, so the caller knows whether there is anything to evict.
    """
    empty_title = title or "Meeting Notes"

    # An empty transcript is not an Ollama failure, and saying so via
    # `Unavailable` would push the UI into showing a remedy for a problem the
    # user does not have. Answer honestly and skip the model entirely — there is
    # nothing to load a multi-gigabyte model for.
    windows = chunk_transcript(segments, budget_chars=budget_chars) if segments else ()
    if not windows:
        resolved = normalize_meeting_type(meeting_type) or DEFAULT_MEETING_TYPE
        note = MeetingNote(title=empty_title, meeting_type=resolved, sections=[])
        _notify(progress, STAGE_RENDER, 1, 1)
        return SummaryResult(
            note=note,
            markdown=render_note(note),
            meeting_type=resolved,
            model=model,
        )

    # Fail fast. Without this a missing model announces itself only after the
    # first map window has spent a minute getting to a 500.
    status = probe(model=model, host=host)
    if isinstance(status, Unavailable):
        return status

    # Past the probe, every path below issues a generation, which is what
    # makes Ollama resident. From here the caller owes an unload.
    loaded.append(True)

    # --- classify -----------------------------------------------------------
    requested = normalize_meeting_type(meeting_type)
    if requested in TEMPLATES:
        resolved_type = requested
    else:
        _notify(progress, STAGE_CLASSIFY, 0, 1)
        resolved_type = _classify(windows=windows, model=model, host=host)
        _notify(progress, STAGE_CLASSIFY, 1, 1)

    template = get_template(resolved_type)

    # --- map ----------------------------------------------------------------
    total = len(windows)
    facts: list[Fact] = []
    first_failure: Optional[Unavailable] = None
    failed = 0

    _notify(progress, STAGE_MAP, 0, total)
    for index, window in enumerate(windows):
        answer = chat_json(
            model=model,
            system=_MAP_SYSTEM,
            user="Extract the facts from this excerpt.\n\n" + render_window(window),
            schema=FACTS_JSON_SCHEMA,
            host=host,
            timeout=MAP_TIMEOUT_SECONDS,
        )
        if isinstance(answer, Unavailable):
            failed += 1
            if first_failure is None:
                first_failure = answer
            _LOG.warning("map window %d/%d unavailable: %s", index + 1, total, answer.reason)
        else:
            facts.extend(parse_facts(answer))
        _notify(progress, STAGE_MAP, index + 1, total)

    # Every window failing means the model or server is gone, not that this
    # meeting was hard. Report the real reason rather than rendering an empty
    # note that looks like a successful summary of nothing.
    if failed == total and first_failure is not None:
        return first_failure

    if failed:
        _LOG.warning("%d of %d map windows failed; note built from the rest", failed, total)

    # --- reduce -------------------------------------------------------------
    _notify(progress, STAGE_REDUCE, 0, 1)

    fact_lines = _facts_prompt(facts)
    user_prompt = (
        f"Write notes for this meeting.\n\nMeeting type: {template.meeting_type}\n"
        + (f"Title: {title}\n" if title else "")
        + "\nFacts:\n"
        + fact_lines
    )

    answer = chat_json(
        model=model,
        system=_REDUCE_SYSTEM,
        user=user_prompt,
        schema=note_schema_for(resolved_type),
        host=host,
        num_ctx=_num_ctx_for(len(user_prompt) + len(_REDUCE_SYSTEM)),
    )
    if isinstance(answer, Unavailable):
        return answer
    _notify(progress, STAGE_REDUCE, 1, 1)

    note = parse_note(
        answer,
        meeting_type=resolved_type,
        fallback_title=empty_title,
    )

    # --- render -------------------------------------------------------------
    _notify(progress, STAGE_RENDER, 0, 1)
    markdown = render_note(note)
    _notify(progress, STAGE_RENDER, 1, 1)

    return SummaryResult(
        note=note,
        markdown=markdown,
        meeting_type=resolved_type,
        model=model,
        facts_used=min(len(facts), MAX_REDUCE_FACTS),
        windows_total=total,
        windows_failed=failed,
    )
