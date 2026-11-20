"""Command-line interface: ``openmind-sandbox``."""

from __future__ import annotations

import openmind_protocol
import typer

import openmind_sandbox

app = typer.Typer(
    name="openmind-sandbox",
    help="Virtual and real objects driven by OpenMind BCI commands.",
    no_args_is_help=True,
    add_completion=False,
)


@app.callback()
def main() -> None:
    """Virtual and real objects driven by OpenMind BCI commands."""


@app.command()
def version() -> None:
    """Print the sandbox and protocol versions."""
    typer.echo(f"openmind-sandbox {openmind_sandbox.__version__}")
    typer.echo(f"openmind-protocol {openmind_protocol.PROTOCOL_VERSION}")


if __name__ == "__main__":  # pragma: no cover
    app()
