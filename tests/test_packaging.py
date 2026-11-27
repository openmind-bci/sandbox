"""The source distribution ships what its own tests read."""

from __future__ import annotations

import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sdist_include() -> list[str]:
    with (ROOT / "pyproject.toml").open("rb") as file:
        config = tomllib.load(file)
    include: list[str] = config["tool"]["hatch"]["build"]["targets"]["sdist"]["include"]
    return include


def test_sdist_ships_the_adapter_template() -> None:
    # tests/test_adapters.py loads template/adapter/my_object.py from the sdist too.
    assert (ROOT / "template" / "adapter" / "my_object.py").is_file()
    assert "template/" in sdist_include()
