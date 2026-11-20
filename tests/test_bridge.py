"""Unit tests of the bridge: framing, client validation, LSL markers and timing."""

import json

import pytest
from openmind_protocol import Command, Event, Marker, ProtocolError

from openmind_sandbox.bridge import (
    MAX_MARKER_DELAY,
    envelope,
    lsl_marker_sample,
    lsl_timestamp,
    parse_client_message,
)


def test_envelope_carries_topic_kind_and_message() -> None:
    command = Command(command="left", confidence=0.8, user="P01", seq=3, ts=10.0)
    frame = json.loads(envelope("openmind/v1/commands", command))
    assert frame == {
        "topic": "openmind/v1/commands",
        "kind": "command",
        "message": {
            "v": 1, "ts": 10.0, "command": "left", "confidence": 0.8, "user": "P01", "seq": 3,
        },
    }  # fmt: skip


def test_client_marker_gets_v_and_ts_when_missing() -> None:
    frame = {"kind": "marker", "message": {"type": "cue", "label": "left", "trial": 2,
                                          "scene": "bird"}}  # fmt: skip
    message = parse_client_message(json.dumps(frame), now=lambda: 123.0)
    assert isinstance(message, Marker)
    assert (message.v, message.ts, message.label, message.trial) == (1, 123.0, "left", 2)


def test_client_event_is_accepted() -> None:
    frame = {"kind": "event", "message": {"object": "twin", "kind": "lap", "data": {"t": 1}}}
    assert isinstance(parse_client_message(json.dumps(frame)), Event)


@pytest.mark.parametrize(
    ("text", "match"),
    [
        ("not json", "not valid JSON"),
        ("[1, 2]", "expected"),
        ('{"kind": "marker"}', "expected"),
        ('{"kind": "command", "message": {}}', "not accepted"),
        ('{"kind": "marker", "message": {"type": "cue", "label": "", "trial": 1, "scene": null}}',
         "label"),
        ('{"kind": "marker", "message": {"v": 2, "type": "cue", "label": "x", "trial": 1,'
         ' "scene": null}}', "version"),
    ],
)  # fmt: skip
def test_invalid_client_frames_are_rejected(text: str, match: str) -> None:
    with pytest.raises(ProtocolError, match=match):
        parse_client_message(text)


def test_lsl_cue_sample_follows_the_stream_spec() -> None:
    marker = Marker(type="cue", label="left", trial=12, scene="calibration")
    sample = json.loads(lsl_marker_sample(marker))
    assert sample == {
        "type": "cue", "label": "left", "trial": 12, "scene": "calibration", "source": "sandbox",
    }  # fmt: skip


def test_lsl_sample_omits_null_fields() -> None:
    sample = json.loads(lsl_marker_sample(Marker(type="event", label="door", trial=None,
                                                 scene=None)))  # fmt: skip
    assert sample == {"type": "event", "label": "door", "source": "sandbox"}


def test_lsl_timestamp_back_dates_by_the_transit_delay() -> None:
    assert lsl_timestamp(marker_ts=99.95, wall_now=100.0, lsl_now=500.0) == pytest.approx(499.95)


@pytest.mark.parametrize("marker_ts", [100.5, 100.0 - MAX_MARKER_DELAY - 0.1])
def test_untrusted_delays_use_the_reception_time(marker_ts: float) -> None:
    assert lsl_timestamp(marker_ts, wall_now=100.0, lsl_now=500.0) == 500.0
