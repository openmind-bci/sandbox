"""Summarise a bridge log of a full-chain run (used by ``run-chain.sh --check``).

Reads the JSON lines written by ``openmind-sandbox bridge --log`` and prints the
commands, statuses, decoder latency events and robot states seen. Exits with 1
when no command or no status was received, 2 when the log is unreadable.
Standard library only.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: summarize_chain.py EVENTS.jsonl", file=sys.stderr)
        return 2
    try:
        lines = Path(argv[1]).read_text(encoding="utf-8").splitlines()
    except OSError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    commands: Counter[str] = Counter()
    states: Counter[str] = Counter()
    decoder_states: Counter[str] = Counter()
    statuses = 0
    latency: list[dict[str, float]] = []
    last_state = "unknown"
    for line in lines:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = record.get("kind")
        message = record.get("message") or {}
        if kind == "command":
            commands[str(message.get("command"))] += 1
        elif kind == "status":
            statuses += 1
            decoder_states[str(message.get("state", message.get("decoder_state", "?")))] += 1
        elif kind == "event":
            data = message.get("data") or {}
            if message.get("object") == "decoder" and message.get("kind") == "latency":
                latency.append(data)
            elif message.get("kind") == "state":
                last_state = str(data.get("state"))
                states[last_state] += 1

    total = sum(commands.values())
    print("Full chain summary")
    print(f"  commands received   {total} ({_fmt(commands)})")
    print(f"  statuses received   {statuses} ({_fmt(decoder_states)})")
    print(f"  robot state changes {sum(states.values())} ({_fmt(states)}); last: {last_state}")
    if latency:
        last = latency[-1]
        print(
            "  decoder latency     "
            f"count {last.get('count')}, mean {last.get('mean_ms')} ms, "
            f"p50 {last.get('p50_ms')} ms, p95 {last.get('p95_ms')} ms, "
            f"max {last.get('max_ms')} ms ({len(latency)} events)"
        )
    else:
        print("  decoder latency     no event yet (one every 10 s once commands flow)")
    if total == 0 or statuses == 0:
        print("FAIL: no command or no status arrived (see docs/full-chain.md, Troubleshooting)")
        return 1
    print("OK")
    return 0


def _fmt(counter: Counter[str]) -> str:
    return ", ".join(f"{k} {v}" for k, v in sorted(counter.items())) or "none"


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
