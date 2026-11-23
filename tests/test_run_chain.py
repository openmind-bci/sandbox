"""The full-chain script: only what is testable without the other repositories."""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

DEV = Path(__file__).resolve().parents[1] / "dev"
SCRIPT = DEV / "run-chain.sh"
SUMMARY = DEV / "summarize_chain.py"

pytestmark = pytest.mark.skipif(
    sys.platform == "win32" or shutil.which("bash") is None, reason="needs bash (not Windows)"
)


def _bash(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args], capture_output=True, text=True, timeout=30, check=False
    )


def test_script_syntax_is_valid() -> None:
    result = subprocess.run(
        ["bash", "-n", str(SCRIPT)], capture_output=True, text=True, check=False
    )
    assert result.returncode == 0, result.stderr


def test_help_lists_the_options() -> None:
    result = _bash("--help")
    assert result.returncode == 0
    for option in ("--synthetic", "--model", "--brain", "--bridge", "--check", "--duration"):
        assert option in result.stdout


def test_unknown_option_is_rejected() -> None:
    result = _bash("--nope")
    assert result.returncode == 2
    assert "unknown option" in result.stderr


def test_missing_repository_is_reported(tmp_path: Path) -> None:
    result = _bash("--plug-dir", str(tmp_path / "absent"), "--core-dir", str(tmp_path))
    assert result.returncode == 2
    assert "repository not found" in result.stderr


def _summarize(log: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SUMMARY), str(log)], capture_output=True, text=True, check=False
    )


def _line(kind: str, message: dict[str, object]) -> str:
    return json.dumps({"topic": f"openmind/v1/{kind}s", "kind": kind, "message": message})


def test_summary_succeeds_with_commands_and_status(tmp_path: Path) -> None:
    log = tmp_path / "events.jsonl"
    log.write_text(
        "\n".join(
            [
                _line("command", {"command": "left"}),
                _line("status", {"state": "running"}),
                _line(
                    "event",
                    {"object": "decoder", "kind": "latency", "data": {"count": 3, "mean_ms": 5.0}},
                ),
                "not json",
            ]
        ),
        encoding="utf-8",
    )
    result = _summarize(log)
    assert result.returncode == 0, result.stdout
    assert "left 1" in result.stdout
    assert "mean 5.0 ms" in result.stdout


def test_summary_fails_without_command(tmp_path: Path) -> None:
    log = tmp_path / "events.jsonl"
    log.write_text(_line("status", {"state": "running"}), encoding="utf-8")
    assert _summarize(log).returncode == 1
