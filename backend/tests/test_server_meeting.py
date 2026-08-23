#!/usr/bin/env python3
"""
Wire-protocol tests for the meeting handlers in `server.py`.

These drive `WebSocketServer` directly against a fake socket and a fake whisper
model, so they assert on the JSON that actually goes out — the thing the Flutter
client is written against — rather than on internal state.

No model is loaded. `WhisperCppBackend.__init__` loads 1.5 GB of weights, so the
backend is built with `object.__new__` and given the two attributes the meeting
path uses. That is deliberate: it keeps the test honest about which parts of the
backend meetings actually touch.

The summarize tests reuse the stdlib Ollama stub from `test_llm` and point the
server at it with ULTRAWHISPER_OLLAMA_HOST.
"""

import asyncio
import json
import threading
from typing import Any, Dict, List

import numpy as np
import pytest

import server as server_module
from meeting import SAMPLE_RATE, TRACK_MIC, TRACK_SYSTEM
from server import WebSocketServer, WhisperCppBackend

from test_llm import _StubOllama, _chat_envelope, stub  # noqa: F401 - `stub` is a fixture

MODEL = "gemma4:e2b"


class FakeSocket:
    """Records every frame the server sends."""

    def __init__(self) -> None:
        self.sent: List[Dict[str, Any]] = []

    async def send(self, raw: str) -> None:
        self.sent.append(json.loads(raw))

    def of_type(self, kind: str) -> List[Dict[str, Any]]:
        return [m for m in self.sent if m.get("type") == kind]

    def types(self) -> List[str]:
        return [m.get("type") for m in self.sent]


class FakeModel:
    """Returns one segment per call, labelled with the call index."""

    def __init__(self) -> None:
        self.calls: List[Dict[str, Any]] = []

    def transcribe(self, audio, language=None, n_threads=4, initial_prompt=None):
        index = len(self.calls)
        self.calls.append({"samples": len(audio), "language": language})
        return {
            "text": f"utterance {index}",
            "segments": [{"text": f"utterance {index}", "t0": 1.0, "t1": 2.0}],
            "language": "en",
        }


def _backend(model=None) -> WhisperCppBackend:
    backend = object.__new__(WhisperCppBackend)
    backend.sessions = {}
    backend.meetings = {}
    backend.model = model or FakeModel()
    backend._model_lock = threading.Lock()
    return backend


def _loud(seconds: float, amplitude: int = 6000) -> bytes:
    """PCM that clears the energy VAD."""
    count = int(seconds * SAMPLE_RATE)
    return (np.ones(count, dtype=np.int16) * amplitude).tobytes()


def _frame(track: int, pcm: bytes) -> bytes:
    return bytes([track]) + pcm


async def _start(srv: WebSocketServer, ws: FakeSocket, **overrides) -> str:
    data = {"meetingId": "m1", "meetingType": "coffee_chat", "windowSeconds": 1}
    data.update(overrides)
    await srv.handle_start_meeting(ws, "cmd-1", data)
    return data["meetingId"]


# ---------------------------------------------------------------------------
# Session lifecycle
# ---------------------------------------------------------------------------


def test_start_meeting_acknowledges_and_arms_audio_routing():
    ws, srv = FakeSocket(), WebSocketServer(_backend())
    asyncio.run(_start(srv, ws))

    assert ws.types() == ["meeting_started"]
    assert ws.sent[0]["data"]["meetingId"] == "m1"
    assert ws.sent[0]["data"]["windowSeconds"] == 1
    assert ws.current_meeting_id == "m1", "binary frames route by this"


def test_start_meeting_without_id_is_rejected():
    ws, srv = FakeSocket(), WebSocketServer(_backend())
    asyncio.run(srv.handle_start_meeting(ws, "cmd-1", {}))

    assert ws.types() == ["error"]
    assert ws.sent[0]["data"]["code"] == "BAD_REQUEST"


def test_end_meeting_keeps_the_transcript_for_summarize():
    """
    end_meeting must NOT free the meeting.

    Summarize still needs it; only cancel drops a transcript.
    """
    ws, srv = FakeSocket(), WebSocketServer(_backend())

    async def scenario():
        await _start(srv, ws)
        await srv.handle_meeting_audio(ws, "m1", _frame(TRACK_MIC, _loud(0.5)))
        await srv.handle_end_meeting(ws, "cmd-2", {"meetingId": "m1"})

    asyncio.run(scenario())

    assert srv.backend.get_meeting("m1") is not None
    assert ws.of_type("meeting_ended")
    assert not hasattr(ws, "current_meeting_id"), "audio routing must be disarmed"


def test_cancel_drops_the_meeting_and_its_transcript():
    ws, srv = FakeSocket(), WebSocketServer(_backend())

    async def scenario():
        await _start(srv, ws)
        await srv.handle_cancel(ws, "cmd-2", {"meetingId": "m1"})

    asyncio.run(scenario())
    assert srv.backend.get_meeting("m1") is None


def test_end_meeting_on_unknown_id_errors():
    ws, srv = FakeSocket(), WebSocketServer(_backend())
    asyncio.run(srv.handle_end_meeting(ws, "cmd-1", {"meetingId": "nope"}))

    assert ws.sent[0]["data"]["code"] == "NO_SUCH_MEETING"


# ---------------------------------------------------------------------------
# Audio and transcript windows
# ---------------------------------------------------------------------------


def test_full_window_emits_a_transcript_window():
    """Both tracks stream concurrently in small chunks, as real capture does."""
    ws, srv = FakeSocket(), WebSocketServer(_backend())

    async def scenario():
        await _start(srv, ws)
        for _ in range(25):  # 25 x 40ms = 1.0s on each track
            await srv.handle_meeting_audio(ws, "m1", _frame(TRACK_MIC, _loud(0.04)))
            await srv.handle_meeting_audio(ws, "m1", _frame(TRACK_SYSTEM, _loud(0.04)))

    asyncio.run(scenario())

    windows = ws.of_type("transcript_window")
    assert len(windows) == 1
    data = windows[0]["data"]
    assert data["meetingId"] == "m1"
    assert data["index"] == 0
    assert (data["t0"], data["t1"]) == (0.0, 1.0)
    assert {s["speaker"] for s in data["segments"]} == {"me", "them"}


def test_track_never_seen_in_a_window_is_absent_from_it():
    """
    An unseen track is treated as absent, not waited for.

    Only tracks that have sent something are held for, so a meeting with no
    system capture still produces windows. In practice this cannot silently
    drop the other side: capture sends chunks every 20-40 ms, so for a track to
    be unseen when a 120s window closes it would have to be absent for the
    whole two minutes — at which point absent is the right reading.
    """
    ws, srv = FakeSocket(), WebSocketServer(_backend())

    async def scenario():
        await _start(srv, ws)
        await srv.handle_meeting_audio(ws, "m1", _frame(TRACK_MIC, _loud(1.0)))

    asyncio.run(scenario())

    windows = ws.of_type("transcript_window")
    assert len(windows) == 1
    assert {s["speaker"] for s in windows[0]["data"]["segments"]} == {"me"}


def test_partial_audio_emits_nothing():
    ws, srv = FakeSocket(), WebSocketServer(_backend())

    async def scenario():
        await _start(srv, ws)
        await srv.handle_meeting_audio(ws, "m1", _frame(TRACK_MIC, _loud(0.4)))

    asyncio.run(scenario())
    assert ws.of_type("transcript_window") == []


def test_window_timestamps_are_absolute_across_windows():
    """
    whisper restarts segment times at zero every call.

    The window offset is what makes the emitted stamps monotonic for the whole
    meeting, which consumers are told they may assume.
    """
    ws, srv = FakeSocket(), WebSocketServer(_backend())

    async def scenario():
        await _start(srv, ws)
        for _ in range(3):
            await srv.handle_meeting_audio(ws, "m1", _frame(TRACK_MIC, _loud(1.0)))

    asyncio.run(scenario())

    windows = ws.of_type("transcript_window")
    assert [w["data"]["index"] for w in windows] == [0, 1, 2]
    starts = [w["data"]["segments"][0]["t0"] for w in windows]
    assert starts == [1.0, 2.0, 3.0], "each window's segment is offset by its window"
    assert starts == sorted(starts)


def test_silent_window_yields_no_segments_and_is_not_an_error():
    """
    One side of a meeting is quiet for minutes at a time.

    A window of pure silence producing nothing is correct, not a failure.
    """
    model = FakeModel()
    ws, srv = FakeSocket(), WebSocketServer(_backend(model))

    async def scenario():
        await _start(srv, ws)
        await srv.handle_meeting_audio(ws, "m1", _frame(TRACK_MIC, _loud(1.0, amplitude=0)))

    asyncio.run(scenario())

    windows = ws.of_type("transcript_window")
    assert len(windows) == 1
    assert windows[0]["data"]["segments"] == []
    assert model.calls == [], "silence must not reach whisper at all"
    assert ws.of_type("error") == []


def test_malformed_frame_is_reported_as_an_error():
    """Accepting a bad frame would put shifted noise under the wrong speaker."""
    ws, srv = FakeSocket(), WebSocketServer(_backend())

    async def scenario():
        await _start(srv, ws)
        await srv.handle_meeting_audio(ws, "m1", b"\x09" + _loud(0.1))

    asyncio.run(scenario())

    errors = ws.of_type("error")
    assert errors and errors[0]["data"]["code"] == "BAD_FRAME"


def test_end_meeting_flushes_the_trailing_partial_window():
    ws, srv = FakeSocket(), WebSocketServer(_backend())

    async def scenario():
        await _start(srv, ws)
        await srv.handle_meeting_audio(ws, "m1", _frame(TRACK_MIC, _loud(0.4)))
        assert ws.of_type("transcript_window") == []
        await srv.handle_end_meeting(ws, "cmd-2", {"meetingId": "m1"})

    asyncio.run(scenario())

    windows = ws.of_type("transcript_window")
    assert len(windows) == 1, "the trailing partial must not be lost"
    assert ws.types()[-1] == "meeting_ended", "the flush precedes the ack"


def test_dictation_audio_is_untouched_by_the_meeting_path():
    """
    The dictation path must behave exactly as before.

    With no meeting on the connection a bare-PCM frame still reaches the
    dictation session, track byte and all framing rules not applied.
    """
    srv = WebSocketServer(_backend())
    ws = FakeSocket()
    session = srv.backend.create_session("s1", {})
    session.is_active = True
    ws.current_session_id = "s1"

    asyncio.run(srv.handle_audio_chunk(ws, _loud(0.1)))

    assert len(session.audio_buffer) == int(0.1 * SAMPLE_RATE)
    assert ws.sent == []


# ---------------------------------------------------------------------------
# Summarization
# ---------------------------------------------------------------------------


NOTE_OK = _chat_envelope(
    json.dumps(
        {
            "title": "Coffee chat",
            "sections": [{"title": "Follow-Ups", "items": [{"text": "Send the deck."}]}],
        }
    )
)
FACTS_OK = _chat_envelope(
    json.dumps({"facts": [{"text": "They ship in Q3.", "speaker": "them", "t0": 1.0}]})
)


def _ollama(monkeypatch, stub_factory, *, tags=None):
    def responder(method, path, body):
        if path.endswith("/api/version"):
            return 200, json.dumps({"version": "0.31.1"})
        if path.endswith("/api/tags"):
            return 200, tags if tags is not None else json.dumps({"models": [{"name": MODEL}]})
        props = ((body or {}).get("format") or {}).get("properties") or {}
        if "facts" in props:
            return 200, FACTS_OK
        return 200, NOTE_OK

    srv = stub_factory(responder)
    monkeypatch.setenv("ULTRAWHISPER_OLLAMA_HOST", srv.host)
    return srv


def _recorded_meeting(srv: WebSocketServer, ws: FakeSocket) -> None:
    async def scenario():
        await _start(srv, ws)
        await srv.handle_meeting_audio(ws, "m1", _frame(TRACK_MIC, _loud(1.0)))
        await srv.handle_end_meeting(ws, "cmd-2", {"meetingId": "m1"})

    asyncio.run(scenario())


def test_summarize_emits_progress_then_a_final_note(stub, monkeypatch):  # noqa: F811
    _ollama(monkeypatch, stub)
    ws, srv = FakeSocket(), WebSocketServer(_backend())
    _recorded_meeting(srv, ws)

    asyncio.run(srv.handle_summarize(ws, "cmd-3", {"meetingId": "m1", "model": MODEL}))

    final = ws.of_type("summary_final")
    assert len(final) == 1
    data = final[0]["data"]
    assert "Send the deck." in data["markdown"]
    assert data["note"]["sections"][0]["title"] == "Follow-Ups"
    assert data["model"] == MODEL
    assert isinstance(data["elapsedSeconds"], float)


def test_summarize_reports_a_missing_model_without_failing(stub, monkeypatch):  # noqa: F811
    """
    summary_unavailable is not an error.

    Ollama being absent must never read as a failed operation, and must never
    cost the user the transcript they already earned.
    """
    _ollama(monkeypatch, stub, tags=json.dumps({"models": [{"name": "other"}]}))
    ws, srv = FakeSocket(), WebSocketServer(_backend())
    _recorded_meeting(srv, ws)

    asyncio.run(srv.handle_summarize(ws, "cmd-3", {"meetingId": "m1", "model": MODEL}))

    assert ws.of_type("error") == [], "this must not be reported as an error"
    unavailable = ws.of_type("summary_unavailable")
    assert len(unavailable) == 1
    assert unavailable[0]["data"]["reason"] == "no_model"
    assert MODEL in unavailable[0]["data"]["remedy"]

    assert srv.backend.get_meeting("m1").segments, "the transcript survives"


def test_summarize_is_repeatable_with_a_different_model(stub, monkeypatch):  # noqa: F811
    """Retrying with a bigger model is the intended response to a weak note."""
    _ollama(monkeypatch, stub,
            tags=json.dumps({"models": [{"name": MODEL}, {"name": "bigger:70b"}]}))
    ws, srv = FakeSocket(), WebSocketServer(_backend())
    _recorded_meeting(srv, ws)

    async def twice():
        await srv.handle_summarize(ws, "a", {"meetingId": "m1", "model": MODEL})
        await srv.handle_summarize(ws, "b", {"meetingId": "m1", "model": "bigger:70b"})

    asyncio.run(twice())
    assert len(ws.of_type("summary_final")) == 2


def test_summarize_without_a_model_is_rejected():
    ws, srv = FakeSocket(), WebSocketServer(_backend())
    _recorded_meeting(srv, ws)
    asyncio.run(srv.handle_summarize(ws, "cmd-3", {"meetingId": "m1"}))

    assert ws.of_type("error")[0]["data"]["code"] == "BAD_REQUEST"


def test_summarize_on_unknown_meeting_errors():
    ws, srv = FakeSocket(), WebSocketServer(_backend())
    asyncio.run(srv.handle_summarize(ws, "cmd-3", {"meetingId": "nope", "model": MODEL}))

    assert ws.of_type("error")[0]["data"]["code"] == "NO_SUCH_MEETING"
