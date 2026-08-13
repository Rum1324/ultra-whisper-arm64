#!/usr/bin/env python3
"""
Tests for `summarize.llm` against a stdlib stub of Ollama.

No real Ollama anywhere: every test spins up an `http.server` on an ephemeral
port and hands the client its address, so the suite passes on a machine that
has never installed Ollama and never touches the GPU.

The failure-path bodies here are copied from real Ollama 0.31.1 responses —
notably the missing-model case, which arrives as HTTP 500 from a crashed model
runner rather than the 404 you would expect.
"""

import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable

import pytest

from summarize import contracts
from summarize.contracts import Unavailable
from summarize.llm import OllamaStatus, chat_json, normalize_model_tag, probe

# A responder maps (method, path, parsed body or None) to (status, body text).
Responder = Callable[[str, str, Any], "tuple[int, str]"]

MODEL = "gemma4:e2b"

# Verified against Ollama 0.31.1: a model that is not pulled, and one whose blob
# is corrupt, both surface identically as a 500 from the crashed runner.
MODEL_LOAD_ERROR_BODY = json.dumps(
    {
        "error": (
            "llama-server process has terminated: exit status 1: "
            "error loading model: unable to load model: "
            "/Users/x/.ollama/models/blobs/sha256-deadbeef"
        )
    }
)


def _chat_envelope(content: str) -> str:
    """The shape `/api/chat` returns: JSON whose message.content is JSON text."""
    return json.dumps(
        {
            "model": MODEL,
            "created_at": "2026-08-12T10:00:00.000000Z",
            "message": {"role": "assistant", "content": content},
            "done": True,
            "done_reason": "stop",
        }
    )


class _StubOllama:
    """A throwaway HTTP server that records what the client sent it."""

    def __init__(self, responder: Responder) -> None:
        self.received: list[dict[str, Any]] = []
        stub = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.0"

            def _handle(self, method: str) -> None:
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                try:
                    body = json.loads(raw) if raw else None
                except ValueError:
                    body = None
                stub.received.append(
                    {
                        "method": method,
                        "path": self.path,
                        "content_type": self.headers.get("Content-Type"),
                        "body": body,
                    }
                )
                status, payload = responder(method, self.path, body)
                encoded = payload.encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)

            def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
                self._handle("GET")

            def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
                self._handle("POST")

            def log_message(self, *args: Any) -> None:
                """Silence the default stderr access log."""

        self._server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        # A short poll interval only matters for teardown: `shutdown()` blocks
        # until the accept loop next wakes, and the 0.5s default would add half
        # a second to every test in this file.
        self._thread = threading.Thread(
            target=self._server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True
        )
        self._thread.start()

    @property
    def host(self) -> str:
        addr, port = self._server.server_address[:2]
        return f"http://{addr}:{port}"

    def close(self) -> None:
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=5)


@pytest.fixture
def stub():
    """Factory fixture; every server it hands out is torn down afterwards."""
    servers: list[_StubOllama] = []

    def _start(responder: Responder) -> _StubOllama:
        server = _StubOllama(responder)
        servers.append(server)
        return server

    yield _start

    for server in servers:
        server.close()


def _ok(payload: str) -> Responder:
    return lambda method, path, body: (200, payload)


def _dead_host() -> str:
    """An address nothing is listening on — bind, read the port, release it."""
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return f"http://127.0.0.1:{port}"


# ---------------------------------------------------------------------------
# Success
# ---------------------------------------------------------------------------


def test_chat_json_returns_the_double_encoded_content(stub):
    note = {"title": "Sync", "sections": [{"title": "Decisions", "items": [{"text": "Ship it"}]}]}
    server = stub(_ok(_chat_envelope(json.dumps(note))))

    result = chat_json(model=MODEL, user="transcript", host=server.host, timeout=5)

    assert result == note


def test_chat_json_sends_the_request_ollama_expects(stub):
    server = stub(_ok(_chat_envelope('{"facts": []}')))
    schema = contracts.FACTS_JSON_SCHEMA

    result = chat_json(
        model=MODEL,
        system="You extract facts.",
        user="[00:00:01] Me: hello",
        schema=schema,
        host=server.host,
        timeout=5,
    )

    assert result == {"facts": []}
    assert len(server.received) == 1
    sent = server.received[0]
    assert sent["method"] == "POST"
    assert sent["path"] == "/api/chat"
    assert sent["content_type"] == "application/json"

    body = sent["body"]
    assert body["model"] == MODEL
    assert body["stream"] is False
    assert body["keep_alive"] == "5m"
    assert body["options"]["temperature"] == 0
    assert body["messages"] == [
        {"role": "system", "content": "You extract facts."},
        {"role": "user", "content": "[00:00:01] Me: hello"},
    ]
    # The schema goes to `format` verbatim: it is Ollama's native structured
    # route, not the OpenAI `response_format` wrapper, and this module must not
    # rewrite what the contract handed it.
    assert body["format"] == json.loads(json.dumps(schema))
    assert "response_format" not in body


def test_chat_json_omits_system_and_format_when_not_given(stub):
    server = stub(_ok(_chat_envelope("{}")))

    chat_json(model=MODEL, user="hi", host=server.host, timeout=5)

    body = server.received[0]["body"]
    assert "format" not in body
    assert body["messages"] == [{"role": "user", "content": "hi"}]


def test_chat_json_passes_num_ctx_only_when_asked(stub):
    server = stub(_ok(_chat_envelope("{}")))

    chat_json(model=MODEL, user="hi", host=server.host, timeout=5, num_ctx=8192)

    assert server.received[0]["body"]["options"]["num_ctx"] == 8192


# ---------------------------------------------------------------------------
# Failure paths
# ---------------------------------------------------------------------------


def test_chat_json_no_server_when_connection_refused():
    result = chat_json(model=MODEL, user="hi", host=_dead_host(), timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "no_server"
    assert result.remedy == "ollama serve"


def test_chat_json_no_model_on_the_real_500_runner_crash(stub):
    server = stub(lambda method, path, body: (500, MODEL_LOAD_ERROR_BODY))

    result = chat_json(model=MODEL, user="hi", host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "no_model"
    assert result.remedy == f"ollama pull {MODEL}"
    assert "error loading model" in result.detail


@pytest.mark.parametrize(
    "body",
    [
        # Ollama 0.31.1, verbatim, for a model that was never pulled.
        json.dumps({"error": f"model '{MODEL}' not found"}),
        # Older phrasing, still in the wild.
        json.dumps({"error": f'model "{MODEL}" not found, try pulling it first'}),
    ],
)
def test_chat_json_no_model_on_404_not_pulled(stub, body):
    server = stub(lambda method, path, b: (404, body))

    result = chat_json(model=MODEL, user="hi", host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "no_model"
    assert result.remedy == f"ollama pull {MODEL}"


def test_chat_json_bad_response_on_unrelated_500(stub):
    """A server fault that says nothing about models must not blame the model."""
    server = stub(lambda method, path, body: (500, json.dumps({"error": "out of memory"})))

    result = chat_json(model=MODEL, user="hi", host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "bad_response"
    assert "out of memory" in result.detail


def test_chat_json_bad_response_when_content_is_not_json(stub):
    server = stub(_ok(_chat_envelope("I'm sorry, I can't summarise that.")))

    result = chat_json(model=MODEL, user="hi", host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "bad_response"
    assert "not valid JSON" in result.detail


def test_chat_json_bad_response_when_message_is_missing(stub):
    server = stub(_ok(json.dumps({"model": MODEL, "done": True})))

    result = chat_json(model=MODEL, user="hi", host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "bad_response"


def test_chat_json_bad_response_when_body_is_not_json(stub):
    server = stub(_ok("<html>502 Bad Gateway</html>"))

    result = chat_json(model=MODEL, user="hi", host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "bad_response"


def test_chat_json_bad_response_when_content_is_a_json_array(stub):
    """Valid JSON, wrong kind — every schema in `contracts` is an object."""
    server = stub(_ok(_chat_envelope("[1, 2, 3]")))

    result = chat_json(model=MODEL, user="hi", host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "bad_response"


def test_chat_json_times_out_without_raising(stub):
    def slow(method: str, path: str, body: Any) -> "tuple[int, str]":
        time.sleep(2.0)
        return 200, _chat_envelope("{}")

    server = stub(slow)

    started = time.monotonic()
    result = chat_json(model=MODEL, user="hi", host=server.host, timeout=0.25)
    elapsed = time.monotonic() - started

    assert isinstance(result, Unavailable)
    assert result.reason == "timeout"
    assert elapsed < 1.5, "the deadline was not enforced"


def test_chat_json_bad_response_when_payload_cannot_be_encoded(stub):
    """A caller-supplied schema that will not serialize is still not an exception."""
    server = stub(_ok(_chat_envelope("{}")))

    result = chat_json(
        model=MODEL,
        user="hi",
        schema={"type": object()},  # type: ignore[dict-item]
        host=server.host,
        timeout=5,
    )

    assert isinstance(result, Unavailable)
    assert result.reason == "bad_response"
    assert server.received == []


@pytest.mark.parametrize(
    "status,payload",
    [
        (200, ""),
        (200, "null"),
        (200, "[]"),
        (200, json.dumps({"message": "a string, not an object"})),
        (200, json.dumps({"message": {"role": "assistant"}})),
        (200, json.dumps({"message": {"content": ""}})),
        (200, json.dumps({"message": {"content": 42}})),
        (204, ""),
        (400, "not json either"),
        (401, json.dumps({"error": "unauthorized"})),
        (500, ""),
        (503, "<html>service unavailable</html>"),
    ],
)
def test_chat_json_never_raises_whatever_the_server_says(stub, status, payload):
    """
    The module's contract in one test.

    `pipeline.py` calls this from a worker thread and forwards the result to the
    UI; an exception escaping here would take the user's transcript down with a
    feature that is only ever an enhancement.
    """
    server = stub(lambda method, path, body: (status, payload))

    result = chat_json(model=MODEL, user="hi", host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason in {"no_server", "no_model", "timeout", "bad_response"}
    assert isinstance(result.detail, str) and result.detail


# ---------------------------------------------------------------------------
# Probe
# ---------------------------------------------------------------------------


def _tags_responder(*names: str) -> Responder:
    version = json.dumps({"version": "0.31.1"})
    tags = json.dumps({"models": [{"name": n, "model": n, "size": 1} for n in names]})

    def respond(method: str, path: str, body: Any) -> "tuple[int, str]":
        if path == "/api/version":
            return 200, version
        if path == "/api/tags":
            return 200, tags
        return 404, json.dumps({"error": "not found"})

    return respond


def test_probe_reports_version_and_models(stub):
    server = stub(_tags_responder(MODEL, "qwen3.6:27b"))

    result = probe(host=server.host, timeout=5)

    assert isinstance(result, OllamaStatus)
    assert result.version == "0.31.1"
    assert result.models == (MODEL, "qwen3.6:27b")
    assert result.has_model(MODEL)
    assert not result.has_model("nope:1b")
    assert [r["method"] for r in server.received] == ["GET", "GET"]


def test_probe_detects_a_missing_model_cheaply(stub):
    server = stub(_tags_responder("qwen3.6:27b"))

    result = probe(model=MODEL, host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "no_model"
    assert result.remedy == f"ollama pull {MODEL}"
    assert MODEL in result.detail


def test_probe_matches_a_bare_name_against_the_latest_tag(stub):
    server = stub(_tags_responder("gemma4:latest"))

    result = probe(model="gemma4", host=server.host, timeout=5)

    assert isinstance(result, OllamaStatus)


def test_probe_no_server_when_nothing_is_listening():
    result = probe(model=MODEL, host=_dead_host(), timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "no_server"
    assert result.remedy == "ollama serve"


def test_probe_bad_response_when_the_port_is_not_ollama(stub):
    server = stub(_ok(json.dumps({"hello": "world"})))

    result = probe(model=MODEL, host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "bad_response"


def test_probe_bad_response_when_tags_are_garbage(stub):
    def respond(method: str, path: str, body: Any) -> "tuple[int, str]":
        if path == "/api/version":
            return 200, json.dumps({"version": "0.31.1"})
        return 200, json.dumps({"models": "not a list"})

    server = stub(respond)

    result = probe(host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "bad_response"


def test_probe_times_out_without_raising(stub):
    def slow(method: str, path: str, body: Any) -> "tuple[int, str]":
        time.sleep(2.0)
        return 200, json.dumps({"version": "0.31.1"})

    server = stub(slow)

    result = probe(host=server.host, timeout=0.25)

    assert isinstance(result, Unavailable)
    assert result.reason == "timeout"


def test_probe_survives_an_empty_model_list(stub):
    server = stub(_tags_responder())

    result = probe(model=MODEL, host=server.host, timeout=5)

    assert isinstance(result, Unavailable)
    assert result.reason == "no_model"


def test_public_entry_points_swallow_caller_type_errors(caplog):
    """
    The backstop, exercised.

    A caller bug must still come back as a value: `pipeline.py` runs this in an
    executor and a raised exception there would abort the whole summarization
    task after the transcript has already been produced.
    """
    bad_chat = chat_json(model=MODEL, user="hi", host=object())  # type: ignore[arg-type]
    bad_probe = probe(host=None)  # type: ignore[arg-type]

    for result in (bad_chat, bad_probe):
        assert isinstance(result, Unavailable)
        assert result.reason == "bad_response"
    # Degraded, but not silent.
    assert "Unhandled error" in caplog.text


@pytest.mark.parametrize(
    "bare,expected",
    [("gemma4", "gemma4:latest"), ("gemma4:e2b", "gemma4:e2b"), ("  gemma4 ", "gemma4:latest")],
)
def test_normalize_model_tag(bare, expected):
    assert normalize_model_tag(bare) == expected
