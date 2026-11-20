"""Single-key terminal input without pressing Enter, arrow keys included (Unix, Windows).

Keys are returned as names: ``"up"``, ``"down"``, ``"left"``, ``"right"``,
``"space"``, or the character itself (``"q"``, ``"+"``...).
"""

from __future__ import annotations

import os
import sys
from collections.abc import Callable, Iterator
from contextlib import contextmanager

#: Escape sequences of the arrow keys (normal and application cursor modes).
_ARROWS = {"A": "up", "B": "down", "C": "right", "D": "left"}
#: Second byte of the arrow keys on Windows (after ``\x00`` or ``\xe0``).
_WINDOWS_ARROWS = {"H": "up", "P": "down", "K": "left", "M": "right"}

KeyReader = Callable[[float], list[str]]


def stdin_is_terminal() -> bool:
    """Whether standard input is an interactive terminal."""
    return sys.stdin is not None and sys.stdin.isatty()


def parse_keys(data: str) -> list[str]:
    """Split raw terminal input into key names.

    >>> parse_keys("\\x1b[Ca \\x1bOD")
    ['right', 'a', 'space', 'left']
    """
    keys: list[str] = []
    i = 0
    while i < len(data):
        char = data[i]
        if char == "\x1b" and i + 2 < len(data) and data[i + 1] in "[O":
            keys.append(_ARROWS.get(data[i + 2], "escape"))
            i += 3
            continue
        if char == "\x1b":
            keys.append("escape")
        elif char == " ":
            keys.append("space")
        else:
            keys.append(char)
        i += 1
    return keys


@contextmanager
def key_reader() -> Iterator[KeyReader]:
    """Put the terminal in single-key mode and yield a ``read(timeout)`` function.

    ``read(timeout)`` returns the keys pressed within ``timeout`` seconds (possibly
    none). Ctrl+C keeps working. The terminal is restored on exit.
    """
    if sys.platform == "win32":
        import msvcrt
        import time

        def read_windows(timeout: float) -> list[str]:
            deadline = time.monotonic() + timeout
            keys: list[str] = []
            while not keys and time.monotonic() < deadline:
                while msvcrt.kbhit():
                    char = msvcrt.getwch()
                    if char in ("\x00", "\xe0"):
                        keys.append(_WINDOWS_ARROWS.get(msvcrt.getwch(), "escape"))
                    else:
                        keys.extend(parse_keys(char))
                if not keys:
                    time.sleep(0.005)
            return keys

        yield read_windows
    else:
        import select
        import termios
        import tty

        fd = sys.stdin.fileno()
        saved = termios.tcgetattr(fd)
        tty.setcbreak(fd)  # keys arrive one by one; Ctrl+C still raises SIGINT

        def read_unix(timeout: float) -> list[str]:
            ready, _, _ = select.select([fd], [], [], timeout)
            if not ready:
                return []
            return parse_keys(os.read(fd, 64).decode("utf-8", errors="replace"))

        try:
            yield read_unix
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, saved)
