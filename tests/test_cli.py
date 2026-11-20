import openmind_protocol
from typer.testing import CliRunner

from openmind_sandbox.cli import app

runner = CliRunner()


def test_version_prints_sandbox_and_protocol_versions() -> None:
    result = runner.invoke(app, ["version"])
    assert result.exit_code == 0
    assert "openmind-sandbox" in result.output
    assert f"openmind-protocol {openmind_protocol.PROTOCOL_VERSION}" in result.output


def test_protocol_major_version_is_supported() -> None:
    assert openmind_protocol.PROTOCOL_VERSION.split(".")[0] == "1"
