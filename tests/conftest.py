"""Skip ``broker`` tests when no MQTT broker is reachable.

Set ``OPENMIND_REQUIRE_BROKER=1`` (as CI does) to fail instead of skipping.
"""

from __future__ import annotations

import os
import socket

import pytest

BROKER_HOST = os.environ.get("OPENMIND_TEST_BROKER", "localhost")
BROKER_PORT = 1883


def _broker_reachable() -> bool:
    try:
        with socket.create_connection((BROKER_HOST, BROKER_PORT), timeout=0.5):
            return True
    except OSError:
        return False


def pytest_collection_modifyitems(config: pytest.Config, items: list[pytest.Item]) -> None:
    if any("broker" in item.keywords for item in items) and not _broker_reachable():
        if os.environ.get("OPENMIND_REQUIRE_BROKER") == "1":
            raise pytest.UsageError(f"no MQTT broker on {BROKER_HOST}:{BROKER_PORT}")
        skip = pytest.mark.skip(reason=f"no MQTT broker on {BROKER_HOST}:{BROKER_PORT}")
        for item in items:
            if "broker" in item.keywords:
                item.add_marker(skip)
