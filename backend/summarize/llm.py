#!/usr/bin/env python3
"""
Synchronous Ollama client for the meeting-note passes.

Deliberately blocking and deliberately stdlib-only. It is called from a worker
thread via `run_in_executor` (the pattern `handle_end_session` already uses), so
blocking here is correct — making it async would buy nothing and would drag an
HTTP library into a backend whose entire dependency budget is `websockets` plus
`numpy`.

Nothing in this module raises. Every failure — no server, no model, timeout,
garbage response — comes back as `contracts.Unavailable`, which `pipeline.py`
forwards to the UI as a `summary_unavailable` event. That is the whole point:
meeting notes are an enhancement layered on a transcript that already works, so
an exception escaping from here would cost the user a transcript they had
already earned. The bare `except Exception` in `_request_json` is load-bearing,
not laziness.

The `format` field is Ollama's native structured-output route: it takes a JSON
Schema object directly, not the OpenAI-compatible `response_format` wrapper.
Schemas are passed through untouched from `contracts.note_json_schema()` /
`contracts.FACTS_JSON_SCHEMA`; this module neither builds nor validates them.
"""

import functools
import json
import logging
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable, Mapping, TypeVar

from .contracts import Unavailable

_LOG = logging.getLogger(__name__)

# Ollama's fixed local port. Not configurable per-call by accident: the caller
# passes `host` explicitly when it wants something else.
DEFAULT_HOST = "http://127.0.0.1:11434"

# Native generate route, used only to evict a model — see `unload`.
GENERATE_PATH = "/api/generate"

CHAT_PATH = "/api/chat"
VERSION_PATH = "/api/version"
TAGS_PATH = "/api/tags"

# One generation, not one summarization run. A reduce pass over an hour of
# facts with a model that has just been evicted from memory pays a cold load of
# the weights (seconds to tens of seconds) before it emits its first token, and
# the user is explicitly invited by the protocol to retry with a bigger model.
# Five minutes is long enough that a slow-but-working call is never mistaken for
# a hung one; the caller narrows it when it knows the pass is small.
DEFAULT_TIMEOUT_SECONDS = 300.0

# The probe exists to fail fast before a multi-minute job, so it gets its own
# much tighter budget. `/api/version` and `/api/tags` are both served from
# memory — if they take five seconds something is wrong anyway.
DEFAULT_PROBE_TIMEOUT_SECONDS = 5.0

# Keep the weights resident between the map windows and the reduce pass.
# Reloading a multi-gigabyte model between every window is the single easiest
# way to turn a one-minute summary into a five-minute one.
DEFAULT_KEEP_ALIVE = "5m"

# Notes must be reproducible enough that "summarize again" is a diagnostic
# rather than a dice roll.
DEFAULT_TEMPERATURE = 0.0

# "The model is not usable" arrives in two different shapes from Ollama 0.31.1,
# and only one of them is the obvious one:
#
#   * never pulled  -> HTTP 404, `{"error": "model 'x:1b' not found"}`
#   * stale/corrupt -> HTTP 500, `{"error": "llama-server process has
#     blob or a runner    terminated: exit status 1: error loading model: ..."}`
#     that dies on load
#
# The second is a crashed subprocess, not an API rejection, so status alone
# cannot distinguish it from a genuine server fault — these substrings are what
# separate "re-pull the model" from "something else broke".
_NO_MODEL_MARKERS = (
    "error loading model",
    "llama-server process has terminated",
    "llama runner process has terminated",
    "unable to load model",
    "try pulling it first",
    "file does not exist",
)

# `detail` is shown to the user, and a model-loading traceback can run to
# kilobytes. Truncate rather than let the UI deal with it.
_MAX_DETAIL_CHARS = 400

_START_SERVER_REMEDY = "ollama serve"

__all__ = [
    "CHAT_PATH",
    "DEFAULT_HOST",
    "DEFAULT_KEEP_ALIVE",
    "unload",
    "DEFAULT_PROBE_TIMEOUT_SECONDS",
    "DEFAULT_TEMPERATURE",
    "DEFAULT_TIMEOUT_SECONDS",
    "TAGS_PATH",
    "VERSION_PATH",
    "OllamaStatus",
    "chat_json",
    "normalize_model_tag",
    "probe",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


_T = TypeVar("_T")


def _never_raises(func: Callable[..., _T]) -> Callable[..., _T | Unavailable]:
    """
    Backstop for this module's no-raise guarantee.

    Every failure this module knows about is already returned as `Unavailable`;
    this catches the ones nobody anticipated — a caller handing us a wrong-typed
    argument, or a behavior difference between the 3.10 dev interpreter and the
    3.12 runtime in the app bundle. Losing the note is acceptable, losing the
    transcript the note was built from is not. It logs at exception level so a
    real bug is still loud in the backend log rather than silently degraded.
    """

    @functools.wraps(func)
    def wrapper(*args: Any, **kwargs: Any) -> _T | Unavailable:
        try:
            return func(*args, **kwargs)
        except Exception as exc:  # noqa: BLE001 - deliberate: see docstring
            _LOG.exception("Unhandled error in summarize.llm.%s", func.__name__)
            return Unavailable(
                reason="bad_response",
                detail=f"Internal error in the summarization client: {exc!r}"[:_MAX_DETAIL_CHARS],
            )

    return wrapper


def _truncate(text: str) -> str:
    text = " ".join(text.split())
    if len(text) <= _MAX_DETAIL_CHARS:
        return text
    return text[: _MAX_DETAIL_CHARS - 1] + "…"


def _is_timeout(exc: BaseException) -> bool:
    """
    True when `exc` means "the deadline passed", however urllib wrapped it.

    A timeout striking during the connect shows up as `URLError(TimeoutError)`,
    while one striking during the read is raised bare (`socket.timeout` is an
    alias for `TimeoutError` on every version we support).
    """
    if isinstance(exc, TimeoutError):
        return True
    return isinstance(getattr(exc, "reason", None), TimeoutError)


def normalize_model_tag(model: str) -> str:
    """
    Resolve a bare model name to the `name:tag` form `/api/tags` reports.

    Ollama treats `gemma4` and `gemma4:latest` as the same model but only ever
    lists the second, so comparing the user's setting to the tag list without
    this produces a spurious `no_model`.
    """
    model = model.strip()
    return model if ":" in model else f"{model}:latest"


def _error_text(body: str) -> str:
    """Pull Ollama's `{"error": ...}` message out of a body, or return it raw."""
    try:
        parsed = json.loads(body)
    except (ValueError, TypeError):
        return body
    if isinstance(parsed, dict) and isinstance(parsed.get("error"), str):
        return parsed["error"]
    return body


def _classify_http_error(status: int, body: str, model: str | None) -> Unavailable:
    """
    Turn a non-2xx response into the right `reason`.

    Status alone is not enough: the missing-model case arrives as a 500 because
    the model-runner subprocess dies rather than the API rejecting the request,
    so the body has to be inspected. Anything we cannot positively identify as a
    model problem stays `bad_response` — claiming `no_model` wrongly sends the
    user off to re-pull a model that was never the problem.
    """
    message = _error_text(body)
    lowered = message.lower()

    looks_like_missing_model = any(marker in lowered for marker in _NO_MODEL_MARKERS)
    if status == 404 and "model" in lowered:
        looks_like_missing_model = True

    if looks_like_missing_model and model:
        return Unavailable(
            reason="no_model",
            detail=_truncate(f"Ollama could not load model {model!r}: {message}"),
            remedy=f"ollama pull {model}",
        )

    return Unavailable(
        reason="bad_response",
        detail=_truncate(f"Ollama returned HTTP {status}: {message}"),
    )


def _request_json(
    url: str,
    *,
    payload: Mapping[str, Any] | None,
    timeout: float,
    model: str | None,
) -> Any | Unavailable:
    """
    Perform one HTTP round trip and parse the body as JSON.

    POSTs when `payload` is given, GETs otherwise. Returns the decoded body or
    an `Unavailable`; the caller never has to guard the call with try/except.
    """
    data: bytes | None = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        try:
            data = json.dumps(payload).encode("utf-8")
        except (TypeError, ValueError) as exc:
            # A schema that will not serialize is a caller bug, but crashing the
            # summarization thread over it still costs the user their note.
            return Unavailable(
                reason="bad_response",
                detail=_truncate(f"Request body could not be encoded: {exc}"),
            )
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        url,
        data=data,
        headers=headers,
        method="POST" if data is not None else "GET",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        try:
            body = exc.read().decode("utf-8", errors="replace")
        except Exception:  # noqa: BLE001 - the body is a nicety, the status is not
            body = ""
        return _classify_http_error(exc.code, body, model)
    except urllib.error.URLError as exc:
        if _is_timeout(exc):
            return Unavailable(
                reason="timeout",
                detail=_truncate(f"Ollama did not respond within {timeout:g}s ({url})"),
            )
        return Unavailable(
            reason="no_server",
            detail=_truncate(f"Could not reach Ollama at {url}: {exc.reason}"),
            remedy=_START_SERVER_REMEDY,
        )
    except TimeoutError:
        return Unavailable(
            reason="timeout",
            detail=_truncate(f"Ollama did not respond within {timeout:g}s ({url})"),
        )
    except OSError as exc:
        # Connection reset mid-stream, and anything else the socket layer throws
        # once urllib has handed off.
        return Unavailable(
            reason="no_server",
            detail=_truncate(f"Connection to Ollama at {url} failed: {exc}"),
            remedy=_START_SERVER_REMEDY,
        )
    except Exception as exc:  # noqa: BLE001 - the module's no-raise guarantee
        _LOG.warning("Unexpected error talking to Ollama at %s: %r", url, exc)
        return Unavailable(
            reason="bad_response",
            detail=_truncate(f"Unexpected error talking to Ollama: {exc!r}"),
        )

    text = raw.decode("utf-8", errors="replace")
    try:
        return json.loads(text)
    except ValueError as exc:
        return Unavailable(
            reason="bad_response",
            detail=_truncate(f"Ollama returned a non-JSON body ({exc}): {text}"),
        )


# ---------------------------------------------------------------------------
# Constrained chat
# ---------------------------------------------------------------------------


@_never_raises
def chat_json(
    *,
    model: str,
    user: str,
    system: str | None = None,
    schema: Mapping[str, Any] | None = None,
    host: str = DEFAULT_HOST,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    keep_alive: str = DEFAULT_KEEP_ALIVE,
    temperature: float = DEFAULT_TEMPERATURE,
    num_ctx: int | None = None,
) -> dict[str, Any] | Unavailable:
    """
    Run one non-streaming chat completion and return the model's parsed JSON.

    `schema` is handed to Ollama's `format` field verbatim — that field takes a
    JSON Schema object directly on the native `/api/chat` route, unlike the
    OpenAI-compatible endpoint's `response_format` wrapper. Passing `None`
    leaves the model unconstrained.

    `num_ctx` is exposed because Ollama silently truncates a prompt that exceeds
    the model's default context window rather than erroring, which shows up as a
    note that quietly forgets the first half of the meeting. Callers that build
    long reduce prompts should set it deliberately.

    Returns the object decoded from `message.content` — Ollama returns that
    content as a *string* of JSON even under `format`, so it takes a second
    `json.loads`. On any failure, returns `Unavailable` instead; this function
    does not raise.
    """
    messages: list[dict[str, str]] = []
    if system is not None:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": user})

    options: dict[str, Any] = {"temperature": temperature}
    if num_ctx is not None:
        options["num_ctx"] = num_ctx

    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": False,
        "keep_alive": keep_alive,
        "options": options,
    }
    if schema is not None:
        payload["format"] = schema

    envelope = _request_json(
        host.rstrip("/") + CHAT_PATH,
        payload=payload,
        timeout=timeout,
        model=model,
    )
    if isinstance(envelope, Unavailable):
        return envelope

    return _parse_content(envelope)


def _parse_content(envelope: Any) -> dict[str, Any] | Unavailable:
    """
    Dig the JSON object out of a `/api/chat` response envelope.

    Every shape complaint lands on `bad_response` rather than an exception,
    including the "constrained decoding still emitted prose" case — which does
    happen, most often when the model was asked for a schema it could not
    satisfy and fell back to an apology.
    """
    if not isinstance(envelope, dict):
        return Unavailable(
            reason="bad_response",
            detail=_truncate(f"Expected a JSON object from Ollama, got {type(envelope).__name__}"),
        )

    message = envelope.get("message")
    if not isinstance(message, dict):
        return Unavailable(
            reason="bad_response",
            detail=_truncate(f"Ollama response has no 'message' object: {sorted(envelope)}"),
        )

    content = message.get("content")
    if not isinstance(content, str) or not content.strip():
        return Unavailable(
            reason="bad_response",
            detail="Ollama response carried no message content.",
        )

    try:
        parsed = json.loads(content)
    except ValueError as exc:
        return Unavailable(
            reason="bad_response",
            detail=_truncate(f"Model output was not valid JSON ({exc}): {content}"),
        )

    if not isinstance(parsed, dict):
        return Unavailable(
            reason="bad_response",
            detail=_truncate(
                f"Model output was valid JSON but not an object: {type(parsed).__name__}"
            ),
        )

    return parsed


# ---------------------------------------------------------------------------
# Availability probe
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class OllamaStatus:
    """A reachable Ollama server and the models it has pulled."""

    version: str
    models: tuple[str, ...]

    def has_model(self, model: str) -> bool:
        wanted = normalize_model_tag(model)
        return any(normalize_model_tag(name) == wanted for name in self.models)


@_never_raises
def unload(
    *,
    model: str,
    host: str = DEFAULT_HOST,
    timeout: float = 30.0,
) -> bool:
    """
    Ask Ollama to evict `model` from memory now.

    Ollama holds a model resident for `keep_alive` (5 minutes by default) after
    the last request, so a 17 GB note model keeps 17 GB of the machine busy long
    after the note is on screen. On a laptop that is the difference between
    "summarising a meeting" and "the machine is unusable for the next five
    minutes". A `keep_alive` of 0 on any request unloads immediately.

    Deliberately NOT done by setting keep_alive=0 on every pipeline call: the
    pipeline makes one classify, N map and one reduce request, and unloading
    between each would re-read the weights from disk every time. Load once,
    work, then evict — which is what calling this at the end achieves.

    Returns whether Ollama acknowledged. Never raises: failing to free memory
    must not fail a note that already succeeded.
    """
    body = _request_json(
        host.rstrip("/") + GENERATE_PATH,
        payload={"model": model, "keep_alive": 0},
        timeout=timeout,
        model=model,
    )
    return not isinstance(body, Unavailable)


@_never_raises
def probe(
    *,
    model: str | None = None,
    host: str = DEFAULT_HOST,
    timeout: float = DEFAULT_PROBE_TIMEOUT_SECONDS,
) -> OllamaStatus | Unavailable:
    """
    Check that Ollama is up, and optionally that `model` is pulled.

    Worth calling before starting a summarization run: a missing model
    otherwise announces itself only after the first map window has spent a
    minute getting to a 500. Two cheap GETs here turn that into an immediate
    `summary_unavailable` with a `remedy` the user can copy.

    Like everything else in this module, returns a value on failure.
    """
    base = host.rstrip("/")

    version_body = _request_json(base + VERSION_PATH, payload=None, timeout=timeout, model=model)
    if isinstance(version_body, Unavailable):
        return version_body
    if not isinstance(version_body, dict) or not isinstance(version_body.get("version"), str):
        return Unavailable(
            reason="bad_response",
            detail=_truncate(f"{base}{VERSION_PATH} did not look like Ollama: {version_body}"),
        )

    tags_body = _request_json(base + TAGS_PATH, payload=None, timeout=timeout, model=model)
    if isinstance(tags_body, Unavailable):
        return tags_body

    names = _extract_model_names(tags_body)
    if names is None:
        return Unavailable(
            reason="bad_response",
            detail=_truncate(f"{base}{TAGS_PATH} did not list models: {tags_body}"),
        )

    status = OllamaStatus(version=version_body["version"], models=names)

    if model is not None and not status.has_model(model):
        return Unavailable(
            reason="no_model",
            detail=_truncate(
                f"Model {model!r} is not pulled. Available: "
                + (", ".join(names) if names else "(none)")
            ),
            remedy=f"ollama pull {model}",
        )

    return status


def _extract_model_names(body: Any) -> tuple[str, ...] | None:
    """Read `/api/tags` leniently; `None` means the body was not that shape."""
    if not isinstance(body, dict):
        return None
    entries = body.get("models")
    if not isinstance(entries, list):
        return None

    names: list[str] = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name") or entry.get("model")
        if isinstance(name, str) and name:
            names.append(name)
    return tuple(names)
