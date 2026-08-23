#!/usr/bin/env python3
"""
Tests for `summarize.pipeline` against the stdlib Ollama stub in `test_llm`.

The stub, the chat envelope shape and the `stub` fixture are reused rather than
re-declared, so there is exactly one description of what Ollama's wire format
looks like in this suite. No real Ollama, no GPU, no network.

The routing helper below dispatches on the JSON Schema each call carries in
`format`, because that is the only thing that distinguishes the three chat
passes on the wire — classify asks for `meetingType`, map for `facts`, reduce
for `sections`.
"""

import json
from typing import Any, Callable, Optional

import pytest

from summarize.contracts import Segment, Unavailable
from summarize.pipeline import (
    MAX_REDUCE_FACTS,
    STAGE_CLASSIFY,
    STAGE_MAP,
    STAGE_REDUCE,
    STAGE_RENDER,
    SummaryResult,
    summarize_meeting,
)

from test_llm import _StubOllama, _chat_envelope, stub  # noqa: F401 - `stub` is a fixture

MODEL = "gemma4:e2b"

VERSION_BODY = json.dumps({"version": "0.31.1"})
TAGS_BODY = json.dumps({"models": [{"name": MODEL}]})


def _segments(count: int = 4) -> list[Segment]:
    """A short two-track transcript with absolute stamps."""
    return [
        Segment(
            t0=float(i * 10),
            t1=float(i * 10 + 8),
            speaker="me" if i % 2 == 0 else "them",
            text=f"Utterance number {i} about the roadmap and the timeline.",
        )
        for i in range(count)
    ]


def _pass_of(body: Any) -> str:
    """Which pipeline pass a chat request belongs to, from its schema."""
    props = ((body or {}).get("format") or {}).get("properties") or {}
    if "meetingType" in props:
        return "classify"
    if "facts" in props:
        return "map"
    if "sections" in props:
        return "reduce"
    return "unknown"


FACTS_OK = _chat_envelope(
    json.dumps({"facts": [{"text": "Ships in Q3.", "speaker": "them", "t0": 10.0}]})
)
NOTE_OK = _chat_envelope(
    json.dumps(
        {
            "title": "Roadmap sync",
            "sections": [
                {"title": "Follow-Ups", "items": [{"text": "Send the timeline."}]},
            ],
        }
    )
)
CLASSIFY_OK = _chat_envelope(json.dumps({"meetingType": "coffee_chat"}))


def _router(
    *,
    classify: str = CLASSIFY_OK,
    facts: str = FACTS_OK,
    note: str = NOTE_OK,
    version: str = VERSION_BODY,
    tags: str = TAGS_BODY,
    map_status: Callable[[int], int] | None = None,
    note_status: int = 200,
) -> Callable[[str, str, Any], "tuple[int, str]"]:
    """Route the stub by endpoint and, for chat, by which pass is calling."""
    calls = {"map": 0}

    def responder(method: str, path: str, body: Any) -> "tuple[int, str]":
        if path.endswith("/api/version"):
            return 200, version
        if path.endswith("/api/tags"):
            return 200, tags
        which = _pass_of(body)
        if which == "classify":
            return 200, classify
        if which == "map":
            index = calls["map"]
            calls["map"] += 1
            status = map_status(index) if map_status else 200
            return status, facts if status == 200 else json.dumps({"error": "boom"})
        if which == "reduce":
            return note_status, note if note_status == 200 else json.dumps({"error": "boom"})
        return 404, json.dumps({"error": f"unexpected {path}"})

    return responder


# ---------------------------------------------------------------------------
# Empty transcript
# ---------------------------------------------------------------------------


def test_empty_transcript_returns_note_without_touching_ollama(stub):  # noqa: F811
    """
    An empty meeting is not an Ollama failure.

    Reporting it as `Unavailable` would push the UI into offering a remedy for
    a problem the user does not have, so the pipeline answers honestly — and
    must not pay to load a model to do it.
    """
    server = stub(_router())
    result = summarize_meeting([], model=MODEL, meeting_type="coffee_chat", host=server.host)

    assert isinstance(result, SummaryResult)
    assert result.note.sections == []
    assert result.meeting_type == "coffee_chat"
    assert server.received == [], "an empty transcript must not reach the network"


def test_empty_transcript_uses_supplied_title(stub):  # noqa: F811
    server = stub(_router())
    result = summarize_meeting(
        [], model=MODEL, meeting_type="generic", title="Coffee with Ana", host=server.host
    )
    assert isinstance(result, SummaryResult)
    assert result.note.title == "Coffee with Ana"
    assert "Coffee with Ana" in result.markdown


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


def test_full_run_produces_note_and_markdown(stub):  # noqa: F811
    server = stub(_router())
    result = summarize_meeting(
        _segments(), model=MODEL, meeting_type="coffee_chat", host=server.host
    )

    assert isinstance(result, SummaryResult)
    assert result.note.title == "Roadmap sync"
    assert [s.title for s in result.note.sections] == ["Follow-Ups"]
    assert "Send the timeline." in result.markdown
    assert result.windows_failed == 0
    assert result.facts_used >= 1


def test_known_meeting_type_skips_classify(stub):  # noqa: F811
    """A calendar-derived type is authoritative; paying to re-derive it is waste."""
    server = stub(_router())
    summarize_meeting(_segments(), model=MODEL, meeting_type="one_on_one", host=server.host)

    passes = [_pass_of(r["body"]) for r in server.received if r["method"] == "POST"]
    assert "classify" not in passes


def test_unknown_meeting_type_triggers_classify(stub):  # noqa: F811
    server = stub(_router())
    result = summarize_meeting(_segments(), model=MODEL, meeting_type=None, host=server.host)

    passes = [_pass_of(r["body"]) for r in server.received if r["method"] == "POST"]
    assert "classify" in passes
    assert isinstance(result, SummaryResult)
    assert result.meeting_type == "coffee_chat", "the classified type must shape the note"


def test_classify_only_sees_the_first_window(stub):  # noqa: F811
    """
    Classification is decided in the opening minutes.

    Sending the whole transcript would cost more than the section menu it buys.
    """
    server = stub(_router())
    summarize_meeting(_segments(40), model=MODEL, meeting_type=None, host=server.host, budget_chars=200)

    classify = next(r for r in server.received if _pass_of(r["body"]) == "classify")
    assert "Utterance number 0" in classify["body"]["messages"][-1]["content"]
    assert "Utterance number 39" not in classify["body"]["messages"][-1]["content"]


# ---------------------------------------------------------------------------
# Degradation
# ---------------------------------------------------------------------------


def test_classify_failure_falls_back_to_generic(stub):  # noqa: F811
    """Losing the ideal headings must never cost the note."""
    server = stub(_router(classify=json.dumps({"nonsense": True})))
    result = summarize_meeting(_segments(), model=MODEL, meeting_type=None, host=server.host)

    assert isinstance(result, SummaryResult)
    assert result.meeting_type == "generic"


def test_classify_off_menu_answer_falls_back_to_generic(stub):  # noqa: F811
    server = stub(_router(classify=_chat_envelope(json.dumps({"meetingType": "board_meeting"}))))
    result = summarize_meeting(_segments(), model=MODEL, meeting_type=None, host=server.host)

    assert isinstance(result, SummaryResult)
    assert result.meeting_type == "generic"


def test_one_failing_map_window_does_not_lose_the_note(stub):  # noqa: F811
    """One window tripping a model bug costs its own facts and nothing else."""
    server = stub(_router(map_status=lambda i: 500 if i == 0 else 200))
    result = summarize_meeting(
        _segments(40), model=MODEL, meeting_type="generic", host=server.host, budget_chars=200
    )

    assert isinstance(result, SummaryResult)
    assert result.windows_failed == 1
    assert result.windows_total > 1
    assert result.note.sections, "surviving windows must still produce content"


def test_every_map_window_failing_reports_the_real_reason(stub):  # noqa: F811
    """
    All windows failing means the server or model is gone.

    Rendering an empty note here would look like a successful summary of a
    meeting where nothing was said.
    """
    server = stub(_router(map_status=lambda i: 500))
    result = summarize_meeting(
        _segments(20), model=MODEL, meeting_type="generic", host=server.host, budget_chars=200
    )

    assert isinstance(result, Unavailable)


def test_reduce_failure_propagates(stub):  # noqa: F811
    """There is no note without the reduce pass."""
    server = stub(_router(note_status=500))
    result = summarize_meeting(_segments(), model=MODEL, meeting_type="generic", host=server.host)

    assert isinstance(result, Unavailable)


def test_missing_model_fails_before_any_generation(stub):  # noqa: F811
    """The probe exists so a missing model does not announce itself a minute in."""
    server = stub(_router(tags=json.dumps({"models": [{"name": "something-else"}]})))
    result = summarize_meeting(_segments(), model=MODEL, meeting_type="generic", host=server.host)

    assert isinstance(result, Unavailable)
    assert result.reason == "no_model"
    assert result.remedy and MODEL in result.remedy
    assert not [r for r in server.received if r["method"] == "POST"]


# ---------------------------------------------------------------------------
# Progress
# ---------------------------------------------------------------------------


def test_progress_reports_every_stage_in_order(stub):  # noqa: F811
    server = stub(_router())
    seen: list[tuple[str, int, int]] = []

    summarize_meeting(
        _segments(20),
        model=MODEL,
        meeting_type=None,
        host=server.host,
        budget_chars=200,
        progress=lambda stage, done, total: seen.append((stage, done, total)),
    )

    stages = [s for s, _, _ in seen]
    assert stages.index(STAGE_CLASSIFY) < stages.index(STAGE_MAP)
    assert stages.index(STAGE_MAP) < stages.index(STAGE_REDUCE)
    assert stages.index(STAGE_REDUCE) < stages.index(STAGE_RENDER)

    map_ticks = [(d, t) for s, d, t in seen if s == STAGE_MAP]
    assert map_ticks[0][0] == 0, "map must report a 0/N tick before the first window"
    assert map_ticks[-1][0] == map_ticks[-1][1], "map must finish at N/N"
    assert [d for d, _ in map_ticks] == sorted(d for d, _ in map_ticks)


def test_progress_callback_that_raises_does_not_lose_the_note(stub):  # noqa: F811
    """
    The callback reaches into the event loop from a worker thread.

    A closed WebSocket is the likeliest thing here to raise, and a note that has
    already cost minutes of compute must survive it.
    """
    server = stub(_router())

    def exploding(stage: str, done: int, total: int) -> None:
        raise RuntimeError("websocket closed")

    result = summarize_meeting(
        _segments(), model=MODEL, meeting_type="generic", host=server.host, progress=exploding
    )
    assert isinstance(result, SummaryResult)


# ---------------------------------------------------------------------------
# Context sizing and truncation
# ---------------------------------------------------------------------------


def test_reduce_sets_num_ctx_explicitly(stub):  # noqa: F811
    """
    Ollama silently truncates an over-long prompt rather than erroring.

    Left unset, a long meeting produces a note that quietly forgets its first
    half — which still looks like a good note.
    """
    server = stub(_router())
    summarize_meeting(_segments(), model=MODEL, meeting_type="generic", host=server.host)

    reduce_call = next(r for r in server.received if _pass_of(r["body"]) == "reduce")
    assert reduce_call["body"]["options"]["num_ctx"] >= 4096


def test_reduce_prompt_carries_speaker_labels(stub):  # noqa: F811
    """
    Per-owner attribution is the entire reason the capture layer keeps two
    tracks; the reduce prompt has to preserve it or the note flattens.
    """
    server = stub(_router())
    summarize_meeting(_segments(), model=MODEL, meeting_type="generic", host=server.host)

    reduce_call = next(r for r in server.received if _pass_of(r["body"]) == "reduce")
    content = reduce_call["body"]["messages"][-1]["content"]
    assert "Them:" in content
    assert "[00:00:10]" in content


def test_reduce_facts_are_capped(stub, caplog):  # noqa: F811
    """Truncation is reported, never silent."""
    many = _chat_envelope(
        json.dumps(
            {
                "facts": [
                    {"text": f"Fact {i}", "speaker": "them", "t0": float(i)} for i in range(200)
                ]
            }
        )
    )
    server = stub(_router(facts=many))
    result = summarize_meeting(
        _segments(40), model=MODEL, meeting_type="generic", host=server.host, budget_chars=200
    )

    assert isinstance(result, SummaryResult)
    assert result.facts_used == MAX_REDUCE_FACTS
    reduce_call = next(r for r in server.received if _pass_of(r["body"]) == "reduce")
    lines = [
        line
        for line in reduce_call["body"]["messages"][-1]["content"].splitlines()
        if line.startswith("[")
    ]
    assert len(lines) == MAX_REDUCE_FACTS
