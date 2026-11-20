import pytest

from openmind_sandbox.keyboard import parse_keys


@pytest.mark.parametrize(
    ("data", "expected"),
    [
        ("\x1b[A\x1b[B\x1b[C\x1b[D", ["up", "down", "right", "left"]),
        ("\x1bOA\x1bOD", ["up", "left"]),  # application cursor mode
        (" q+", ["space", "q", "+"]),
        ("\x1b", ["escape"]),
        ("", []),
    ],
)
def test_parse_keys(data: str, expected: list[str]) -> None:
    assert parse_keys(data) == expected
