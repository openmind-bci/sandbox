import json
import threading
import time
import uuid

import pytest

from openmind_sandbox.eeg_relay import MAX_FRAME_S, eeg_frame


def test_frame_is_compact_and_bounded() -> None:
    samples = [[float(i), -float(i) + 0.04] for i in range(1000)]
    stamps = [i / 250 for i in range(1000)]
    frame = json.loads(eeg_frame(["C3", "C4"], 250.0, samples, stamps))
    assert frame["kind"] == "eeg"
    assert frame["labels"] == ["C3", "C4"]
    assert len(frame["samples"]) == int(MAX_FRAME_S * 250)  # older samples dropped
    assert frame["samples"][-1] == [999.0, round(-999 + 0.04, 1)]
    assert frame["t0"] == pytest.approx(stamps[-250], abs=1e-4)


@pytest.mark.broker  # needs local LSL networking, run with the integration tests
def test_relay_reads_an_lsl_eeg_stream() -> None:
    import pylsl

    from openmind_sandbox.eeg_relay import EegRelay

    def eeg_outlet(source_id: str, labels: tuple[str, str]) -> pylsl.StreamOutlet:
        info = pylsl.StreamInfo("openmind-eeg", "EEG", 2, 250, pylsl.cf_float32, source_id)
        channels = info.desc().append_child("channels")
        for label in labels:
            channels.append_child("channel").append_child_value("label", label)
        return pylsl.StreamOutlet(info)

    # Another openmind-eeg stream on the machine (plug streaming, say) must not be picked.
    other = eeg_outlet(f"test:other:{uuid.uuid4()}", ("Fp1", "O1"))
    source_id = f"test:relay:{uuid.uuid4()}"
    outlet = eeg_outlet(source_id, ("C3", "C4"))
    frames: list[dict[str, object]] = []
    lock = threading.Lock()

    def sink(text: str) -> None:
        with lock:
            frames.append(json.loads(text))

    relay = EegRelay(sink, resolve_timeout=1.0, source_id=source_id)
    relay.start()
    try:
        assert relay.stream_found.wait(10)
        for i in range(250):
            outlet.push_sample([float(i), 1.0])
            time.sleep(0.002)
        time.sleep(0.5)
    finally:
        relay.stop()
    with lock:
        received = [row for f in frames for row in f["samples"]]  # type: ignore[attr-defined]
    del other
    assert frames and all(f["labels"] == ["C3", "C4"] for f in frames)
    assert len(received) >= 200
