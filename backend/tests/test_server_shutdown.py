#!/usr/bin/env python3
"""
SIGTERM must stop the backend promptly.

The app sends SIGTERM to restart the backend on a model change and to stop it
on quit. It used to log "Shutting down server..." and then never exit: the
`signal.signal` handler called `server.close()` from inside the interrupted
`kevent`, which only scheduled a task, and an idle loop went back to sleep
with no timeout. These tests run a real process and a real signal, because
that wakeup is the bug.
"""

import os
import signal
import subprocess
import sys
import textwrap
import time
from pathlib import Path

import pytest
from websockets.sync.client import connect

import server

BACKEND = Path(__file__).resolve().parent.parent

# A stand-in for server.py's main(): the same serve_until_signalled, without a
# whisper model. "stuck" mode parks the connection handler on an executor
# thread for longer than any test, like a whisper inference or a summary.
SCRIPT = textwrap.dedent("""
    import asyncio, sys, time
    import websockets
    import server

    async def handler(websocket):
        if sys.argv[1] == "stuck":
            await asyncio.get_running_loop().run_in_executor(None, time.sleep, 60)
        async for _ in websocket:
            pass

    async def main():
        srv = await websockets.serve(handler, "127.0.0.1", 0)
        print(f"SERVER_PORT:{srv.sockets[0].getsockname()[1]}", flush=True)
        await server.serve_until_signalled(srv)

    asyncio.run(main())
""")


def start(mode: str):
    proc = subprocess.Popen(
        [sys.executable, "-c", SCRIPT, mode],
        cwd=BACKEND,
        env={**os.environ, "PYTHONPATH": str(BACKEND)},
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    line = proc.stdout.readline()
    assert line.startswith("SERVER_PORT:"), line
    return proc, int(line.split(":")[1])


def seconds_to_exit_after(proc, signum) -> float:
    started = time.monotonic()
    proc.send_signal(signum)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        pytest.fail("backend did not exit within 5 s of the signal")
    assert proc.returncode == 0
    return time.monotonic() - started


@pytest.mark.parametrize("signum", [signal.SIGTERM, signal.SIGINT])
def test_idle_server_exits_on_signal(signum):
    proc, _ = start("idle")
    assert seconds_to_exit_after(proc, signum) < 1.0


def test_exits_with_a_client_connected():
    proc, port = start("idle")
    with connect(f"ws://127.0.0.1:{port}") as ws:
        ws.send("hello")
        assert seconds_to_exit_after(proc, signal.SIGTERM) < 1.0


def test_exits_while_a_handler_is_stuck_on_an_executor_thread():
    proc, port = start("stuck")
    with connect(f"ws://127.0.0.1:{port}", close_timeout=0.1):
        elapsed = seconds_to_exit_after(proc, signal.SIGTERM)
    assert elapsed < 2.0
    assert elapsed >= server.SHUTDOWN_GRACE_S - 0.1  # the grace period was honoured
