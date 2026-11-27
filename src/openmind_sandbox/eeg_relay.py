"""Read-only relay of the LSL EEG stream to WebSocket clients, for the signal panel.

The bridge (``openmind-sandbox bridge --eeg``) reads the ``openmind-eeg`` stream
of OpenMind Plug and sends it to the cockpit about 10 times per second, as
compact frames::

    {"kind": "eeg", "srate": 250.0, "labels": ["FC3", ...], "unit": "microvolts",
     "t0": 1234.567, "samples": [[1.2, -0.4, ...], ...]}

Values are rounded to 0.1 µV and a frame carries at most ``MAX_FRAME_S`` seconds,
so a slow client never receives an ever-growing backlog. The relay never writes
anything to the stream and keeps nothing.
"""

from __future__ import annotations

import json
import logging
import threading
from collections.abc import Callable
from typing import Any, Final

log = logging.getLogger(__name__)

STREAM_NAME: Final = "openmind-eeg"
STREAM_TYPE: Final = "EEG"
#: Seconds between two frames.
FRAME_PERIOD_S: Final = 0.1
#: Largest span of samples sent in one frame (older samples are dropped).
MAX_FRAME_S: Final = 1.0

FrameSink = Callable[[str], None]


def channel_labels(info: Any) -> list[str]:
    """Labels from ``desc/channels/channel/label`` of an LSL stream info."""
    labels: list[str] = []
    channel = info.desc().child("channels").child("channel")
    while not channel.empty():
        labels.append(channel.child_value("label"))
        channel = channel.next_sibling()
    count = int(info.channel_count())
    if len(labels) != count:
        labels = [f"ch{i + 1}" for i in range(count)]
    return labels


def eeg_frame(
    labels: list[str], srate: float, samples: list[list[float]], timestamps: list[float]
) -> str:
    """JSON text frame for a chunk of samples (rows = samples)."""
    if srate > 0:
        keep = max(1, int(MAX_FRAME_S * srate))
        samples, timestamps = samples[-keep:], timestamps[-keep:]
    return json.dumps(
        {
            "kind": "eeg",
            "srate": srate,
            "labels": labels,
            "unit": "microvolts",
            "t0": round(timestamps[0], 4) if timestamps else 0.0,
            "samples": [[round(v, 1) for v in row] for row in samples],
        },
        separators=(",", ":"),
    )


class EegRelay:
    """Background reader of the EEG stream; calls ``sink`` with each frame.

    Args:
        sink: Receives the JSON frames (from the relay thread).
        resolve_timeout: Seconds of each search for the stream.
        source_id: Relay only the stream with this LSL ``source_id`` (when
            several ``openmind-eeg`` streams run); ``None`` takes the first found.
    """

    def __init__(
        self, sink: FrameSink, resolve_timeout: float = 2.0, source_id: str | None = None
    ) -> None:
        self._sink = sink
        self._resolve_timeout = resolve_timeout
        self._source_id = source_id
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="eeg-relay", daemon=True)
        self.frames = 0
        self.stream_found = threading.Event()

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=5)

    def _run(self) -> None:
        import pylsl

        while not self._stop.is_set():
            predicate = f"name='{STREAM_NAME}' and type='{STREAM_TYPE}'"
            if self._source_id is not None:
                predicate += f" and source_id='{self._source_id}'"
            streams = pylsl.resolve_bypred(predicate, 1, self._resolve_timeout)
            if not streams:
                continue
            inlet = pylsl.StreamInlet(streams[0], max_buflen=2)
            try:
                info = inlet.info(timeout=5.0)
                labels = channel_labels(info)
                srate = float(info.nominal_srate())
                self.stream_found.set()
                log.info("Relaying EEG stream %s (%d channels)", info.source_id(), len(labels))
                self._relay(inlet, labels, srate)
            except Exception as error:  # stream lost: search again
                log.warning("EEG stream lost (%s); searching again", error)
            finally:
                inlet.close_stream()

    def _relay(self, inlet: Any, labels: list[str], srate: float) -> None:
        while not self._stop.is_set():
            samples, timestamps = inlet.pull_chunk(timeout=FRAME_PERIOD_S, max_samples=1024)
            if samples:
                self._sink(eeg_frame(labels, srate, samples, timestamps))
                self.frames += 1
