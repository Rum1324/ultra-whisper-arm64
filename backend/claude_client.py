#!/usr/bin/env python3
"""
Claude API client for the dictation formatter — the one place this app sends
text off the Mac, and only when the user picked "Claude" in Settings and gave
their own API key.

Same contract as `summarize/llm.py`: nothing here raises. Every failure — no
key, no network, bad key, credits at $0, rate limit, timeout, refusal — comes
back as a `ClaudeUnavailable`, and the formatter pastes the rule-based text it
already has. Claude is an enhancement, never a dependency of transcription.

The key arrives with each `start_session` from the app, which keeps it in the
macOS Keychain. It is never logged and never written to disk here; it lives in
memory only as long as the cached client below.

Haiku 5.5 was picked by measurement (2026-10-08, the same EN/JA samples and
prompt as gemma4:e4b): 0.8 s median and 0.9 s worst after you stop talking,
against gemma's 3.7 s median and 6.6 s worst when the model has to load; about
$0.0001 per dictation. Sonnet 5.5 and Opus 5.5 were slower and 20-45× the price
without a difference on those samples worth paying for.
"""

import logging
import threading
from dataclasses import dataclass

_LOG = logging.getLogger(__name__)

MODEL = "claude-haiku-5-5"

# A dictation's clean-up is about as long as the dictation, and the longest
# realistic one is a few minutes of speech — well under this.
MAX_TOKENS = 4096


@dataclass(frozen=True)
class ClaudeUnavailable:
    reason: str  # no_key, no_sdk, auth, credits, rate_limit, timeout, offline, refusal, truncated, api_error
    detail: str


# One client per key, so the TLS connection is reused across dictations: the
# first request on a fresh client measured 1.1 s against 0.8 s for later ones.
_clients: dict[str, object] = {}

# How long an idle connection stays open. The SDK's default is 5 s, shorter
# than the gap between almost any two dictations, so every one paid a fresh
# DNS + TCP + TLS handshake after the user stopped talking.
KEEPALIVE_SECONDS = 300.0

# The warm-up request below is a model lookup: a GET that uses no tokens and
# is not billed. It only exists to open the connection while the user speaks.
WARM_TIMEOUT = 3.0
_lock = threading.Lock()


def _client(api_key: str):
    import anthropic  # deferred: pydantic and friends cost startup time for every user

    with _lock:
        client = _clients.get(api_key)
        if client is None:
            # No retries: a retry doubles the worst-case wait, and the fallback
            # (the rule-based text) is already in hand.
            import httpx2  # the HTTP library this SDK version ships on

            client = anthropic.Anthropic(
                api_key=api_key,
                max_retries=0,
                http_client=anthropic.DefaultHttpxClient(
                    limits=httpx2.Limits(
                        max_connections=4,
                        max_keepalive_connections=2,
                        keepalive_expiry=KEEPALIVE_SECONDS,
                    )
                ),
            )
            _clients.clear()  # a changed key replaces the old one
            _clients[api_key] = client
        return client


def warm(api_key: str | None) -> bool:
    """
    Open the connection to api.anthropic.com while the user is still speaking.

    Building the client alone connects to nothing, so this also looks the model
    up — free, no tokens — which leaves a warm TLS connection in the pool for
    the formatting request that follows.
    """
    if not api_key:
        return False
    try:
        _client(api_key).with_options(timeout=WARM_TIMEOUT).models.retrieve(MODEL)
        return True
    except Exception as exc:  # noqa: BLE001 - warming is best-effort
        _LOG.info("Claude warm-up skipped: %s", type(exc).__name__)
        return False


def chat_text(
    *,
    messages: list[dict[str, str]],
    api_key: str | None,
    timeout: float,
    model: str = MODEL,
) -> str | ClaudeUnavailable:
    """
    Run the formatter's message list (system first, then few-shot turns) on Claude.

    Returns the reply text, or why there is none. Never raises.
    """
    if not api_key:
        return ClaudeUnavailable("no_key", "No Anthropic API key saved in Settings.")
    try:
        import anthropic
    except ImportError:
        return ClaudeUnavailable("no_sdk", "The anthropic package is not in this Python.")

    system = "\n\n".join(m["content"] for m in messages if m["role"] == "system")
    turns = [m for m in messages if m["role"] != "system"]
    try:
        response = _client(api_key).with_options(timeout=timeout).messages.create(
            model=model,
            max_tokens=MAX_TOKENS,
            system=system,
            messages=turns,
        )
    except anthropic.AuthenticationError:
        return ClaudeUnavailable("auth", "The API key was rejected.")
    except anthropic.PermissionDeniedError:
        return ClaudeUnavailable("auth", "The API key may not use this model.")
    except anthropic.RateLimitError:
        return ClaudeUnavailable("rate_limit", "Rate limited, or the workspace spend limit was reached.")
    except anthropic.BadRequestError as exc:
        # Out of credits is a 400 whose message says so; tell it apart in the log.
        reason = "credits" if "credit" in str(exc.message).lower() else "api_error"
        return ClaudeUnavailable(reason, _short(exc.message))
    except anthropic.APITimeoutError:
        return ClaudeUnavailable("timeout", f"No reply within {timeout:g}s.")
    except anthropic.APIConnectionError:
        return ClaudeUnavailable("offline", "Could not reach api.anthropic.com.")
    except anthropic.APIStatusError as exc:
        return ClaudeUnavailable("api_error", f"HTTP {exc.status_code}")
    except Exception as exc:  # noqa: BLE001 - the transcript must survive anything
        return ClaudeUnavailable("api_error", type(exc).__name__)

    if response.stop_reason == "refusal":
        return ClaudeUnavailable("refusal", "Claude declined to format this dictation.")
    if response.stop_reason == "max_tokens":
        return ClaudeUnavailable("truncated", "The reply hit max_tokens.")
    text = "".join(block.text for block in response.content if block.type == "text")
    if not text.strip():
        return ClaudeUnavailable("api_error", "The reply carried no text.")
    return text


def _short(text: object) -> str:
    text = str(text)
    return text if len(text) <= 200 else text[:197] + "..."
