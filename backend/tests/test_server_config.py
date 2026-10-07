#!/usr/bin/env python3
"""
Where the backend finds its whisper model and its Ollama.

Both used to be fixed: the model was bundled at one path, and Ollama was always
the default port. A release now downloads the model at first run and may run a
private Ollama on another port, so the app names both — and an older client or
a bare `python server.py` must still get what it used to.
"""

from pathlib import Path

import server


def test_model_flag_wins_over_environment(monkeypatch):
    monkeypatch.setenv("ULTRAWHISPER_MODEL", "/env/ggml-small.bin")
    assert server.resolve_model_path("/flag/ggml-tiny.bin") == Path("/flag/ggml-tiny.bin")


def test_model_from_environment_when_no_flag(monkeypatch):
    monkeypatch.setenv("ULTRAWHISPER_MODEL", "/env/ggml-small.bin")
    assert server.resolve_model_path(None) == Path("/env/ggml-small.bin")


def test_model_defaults_to_the_formerly_bundled_turbo(monkeypatch):
    monkeypatch.delenv("ULTRAWHISPER_MODEL", raising=False)
    assert server.resolve_model_path(None).name == "ggml-large-v3-turbo.bin"


def test_model_path_expands_home(monkeypatch):
    monkeypatch.setenv("HOME", "/Users/someone")
    assert server.resolve_model_path("~/m.bin") == Path("/Users/someone/m.bin")


def test_requested_ollama_host_wins(monkeypatch):
    monkeypatch.setenv("ULTRAWHISPER_OLLAMA_HOST", "http://127.0.0.1:9999")
    assert server.ollama_host("http://127.0.0.1:11435") == "http://127.0.0.1:11435"


def test_ollama_host_falls_back_to_environment_then_default(monkeypatch):
    monkeypatch.setenv("ULTRAWHISPER_OLLAMA_HOST", "http://127.0.0.1:9999")
    assert server.ollama_host(None) == "http://127.0.0.1:9999"
    monkeypatch.delenv("ULTRAWHISPER_OLLAMA_HOST")
    assert server.ollama_host("") == server.OLLAMA_DEFAULT_HOST
