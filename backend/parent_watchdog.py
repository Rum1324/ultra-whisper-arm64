"""
Exit the backend when the app that launched it goes away.

macOS does not kill a child when its parent dies; the child is reparented to
launchd (PPID 1) and keeps running. For this backend that means an orphan still
listening on 8082 — observed 2026-10-06 after `osascript -e 'quit app
"UltraWhisper"'`, which terminates the app without running its Dart cleanup.
A crash or `kill -9` of the app does the same. Cleanup in the app can never
cover those cases, so the backend watches for itself.

The watch is a kqueue EVFILT_PROC/NOTE_EXIT registration on the parent pid,
blocking on a daemon thread: the kernel wakes it exactly once, when the parent
exits, and it costs nothing while idle. Platforms without kqueue fall back to
polling `os.getppid()`.
"""

import logging
import os
import select
import threading
import time
from typing import Callable, Optional

logger = logging.getLogger(__name__)

POLL_INTERVAL_S = 1.0


def _exit_now() -> None:
    # os._exit rather than sys.exit or a graceful server.close(): nobody is
    # left to talk to, the backend keeps no state on disk, and a graceful path
    # can stall behind a whisper inference on an executor thread — which is
    # exactly the kind of process that lingers.
    logger.info("Parent process is gone; exiting")
    os._exit(0)


def _wait_kqueue(parent_pid: int) -> None:
    kq = select.kqueue()
    try:
        event = select.kevent(
            parent_pid,
            filter=select.KQ_FILTER_PROC,
            flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
            fflags=select.KQ_NOTE_EXIT,
        )
        try:
            kq.control([event], 0)
        except ProcessLookupError:
            return  # already gone before we could register
        kq.control(None, 1)  # blocks until the parent exits
    finally:
        kq.close()


def _wait_polling(parent_pid: int) -> None:
    while os.getppid() == parent_pid:
        time.sleep(POLL_INTERVAL_S)


def wait_for_exit(parent_pid: int) -> None:
    """Block until `parent_pid` has exited."""
    if hasattr(select, "kqueue"):
        _wait_kqueue(parent_pid)
    else:
        _wait_polling(parent_pid)


def start(parent_pid: int, on_exit: Optional[Callable[[], None]] = None) -> threading.Thread:
    """
    Call `on_exit` (default: exit the process) once `parent_pid` exits.

    Returns immediately; the wait runs on a daemon thread. If the parent is
    already gone — including the case where we were reparented to launchd
    before this ran — `on_exit` fires straight away.
    """
    callback = on_exit or _exit_now

    def run() -> None:
        if os.getppid() == 1 and parent_pid != 1:
            callback()
            return
        wait_for_exit(parent_pid)
        callback()

    thread = threading.Thread(target=run, name="parent-watchdog", daemon=True)
    thread.start()
    logger.info(f"Watching parent pid {parent_pid}")
    return thread
