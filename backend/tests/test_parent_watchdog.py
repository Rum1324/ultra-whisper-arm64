#!/usr/bin/env python3
"""
The backend must not outlive the app that launched it.

These use real processes: the bug being guarded against (an orphan reparented
to launchd, still holding 8082) only exists between processes, and the default
exit path is `os._exit`, which nothing in-process can observe.
"""

import os
import signal
import subprocess
import sys
import textwrap
import threading
import time
from pathlib import Path

import pytest

import parent_watchdog

BACKEND_DIR = str(Path(__file__).resolve().parent.parent)


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def _wait_until(predicate, timeout: float = 5.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


def test_callback_fires_when_watched_process_exits():
    sleeper = subprocess.Popen(["sleep", "30"])
    fired = threading.Event()
    try:
        parent_watchdog.start(sleeper.pid, on_exit=fired.set)
        time.sleep(0.2)
        assert not fired.is_set(), "fired while the process was still running"

        sleeper.kill()
        sleeper.wait()
        assert fired.wait(5), "did not notice the process exit"
    finally:
        if sleeper.poll() is None:
            sleeper.kill()


def test_callback_fires_at_once_for_a_pid_that_is_already_gone():
    gone = subprocess.Popen(["true"])
    gone.wait()
    fired = threading.Event()

    parent_watchdog.start(gone.pid, on_exit=fired.set)

    assert fired.wait(5)


@pytest.mark.parametrize("parent_death", [signal.SIGKILL, signal.SIGTERM])
def test_backend_exits_when_its_parent_dies(parent_death):
    """
    The real shape of the bug: app -> backend. Kill the "app" and the
    "backend" must go too, instead of living on with PPID 1.
    """
    backend = textwrap.dedent(
        """
        import os, sys, time
        sys.path.insert(0, sys.argv[1])
        import parent_watchdog
        parent_watchdog.start(os.getppid())
        time.sleep(60)
        """
    )
    app = textwrap.dedent(
        """
        import subprocess, sys, time
        child = subprocess.Popen([sys.executable, "-c", sys.argv[1], sys.argv[2]])
        print(child.pid, flush=True)
        time.sleep(60)
        """
    )
    proc = subprocess.Popen(
        [sys.executable, "-c", app, backend, BACKEND_DIR],
        stdout=subprocess.PIPE,
        text=True,
    )
    backend_pid = int(proc.stdout.readline())
    try:
        time.sleep(0.5)  # let the watchdog register
        assert _alive(backend_pid)

        proc.send_signal(parent_death)
        proc.wait()

        assert _wait_until(lambda: not _alive(backend_pid)), (
            f"backend {backend_pid} outlived its parent"
        )
    finally:
        if _alive(backend_pid):
            os.kill(backend_pid, signal.SIGKILL)
        if proc.poll() is None:
            proc.kill()
