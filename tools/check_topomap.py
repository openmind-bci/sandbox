"""2D check of the band power messages: an MNE topographic map seen from above.

Subscribes to ``openmind/v1/bandpower`` and draws the electrodes with the same
diverging scale as the 3D brain panel (blue = decrease, orange = increase,
±0.5), to compare both when in doubt. Electrodes reported ``ok: false`` are
left out of the interpolation and drawn as grey crosses.

MNE and matplotlib are only needed here::

    uv run --with "mne>=1.7" --with matplotlib python tools/check_topomap.py
    uv run --with "mne>=1.7" --with matplotlib python tools/check_topomap.py \\
        --once --output topomap.png      # one message, saved to a file
"""

from __future__ import annotations

import argparse
import queue
import sys
from typing import Any

from openmind_protocol import BandPower, ProtocolError, decode_topic, topics

from openmind_sandbox.mqtt import DEFAULT_HOST, DEFAULT_PORT, BrokerUnavailableError, MqttLink

#: Same colours as godot/panels/brain/brain_colors.gd.
DECREASE = "#2F6FDF"
ZERO = "#E9ECF2"
INCREASE = "#E8892B"
VMAX = 0.5


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--band", choices=["rel_mu", "rel_beta"], default="rel_mu")
    parser.add_argument("--once", action="store_true", help="draw one message and exit")
    parser.add_argument("--output", help="save the map to this image file")
    parser.add_argument("--timeout", type=float, default=10.0, help="seconds to wait (--once)")
    args = parser.parse_args(argv)

    import matplotlib

    if args.output:
        matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import LinearSegmentedColormap

    cmap = LinearSegmentedColormap.from_list("openmind", [DECREASE, ZERO, INCREASE])
    inbox: queue.Queue[BandPower] = queue.Queue(maxsize=4)

    def on_message(topic: str, payload: bytes) -> None:
        try:
            message = decode_topic(topic, payload)
        except ProtocolError as error:
            print(f"rejected: {error}", file=sys.stderr)
            return
        if isinstance(message, BandPower):
            if inbox.full():
                inbox.get_nowait()
            inbox.put_nowait(message)

    link = MqttLink(args.host, args.port, name="openmind-topomap", on_message=on_message)
    link.subscribe([topics.BANDPOWER])
    try:
        link.connect()
    except BrokerUnavailableError as error:
        print(error, file=sys.stderr)
        return 1

    figure, axes = plt.subplots(figsize=(5, 5))
    try:
        while True:
            try:
                message = inbox.get(timeout=args.timeout if args.once else 0.5)
            except queue.Empty:
                if args.once:
                    print("no bandpower message received", file=sys.stderr)
                    return 1
                plt.pause(0.05)
                continue
            summary = draw(message, args.band, axes, cmap)
            print(summary)
            if args.output:
                figure.savefig(args.output, dpi=120, bbox_inches="tight")
                print(f"saved {args.output}")
            if args.once:
                return 0
            plt.pause(0.3)
    except KeyboardInterrupt:
        return 0
    finally:
        link.close()


def draw(message: BandPower, band: str, axes: Any, cmap: Any) -> str:
    """Draw ``message`` on ``axes``; return a one-line summary (lowest electrode)."""
    import mne
    import numpy as np

    good = [c for c in message.channels if c.ok and getattr(c, band) is not None]
    bad = [c.label for c in message.channels if c not in good]
    axes.clear()
    if len(good) < 3:
        return "fewer than 3 usable electrodes: nothing to interpolate"
    info = mne.create_info([c.label for c in good], message.srate_hz, "eeg")
    template = standard_montage_name()
    info.set_montage(template, on_missing="ignore")
    values = np.array([float(getattr(c, band)) for c in good])
    mne.viz.plot_topomap(
        values, info, axes=axes, cmap=cmap, vlim=(-VMAX, VMAX), names=info.ch_names,
        show=False, contours=0, sensors=True,
    )  # fmt: skip
    if bad:
        montage = mne.channels.make_standard_montage(template).get_positions()["ch_pos"]
        for label in bad:
            if label in montage:
                x, y, _ = montage[label]
                axes.plot(x, y, "x", color="#8A8F99", markersize=9)
    lowest = good[int(np.argmin(values))]
    axes.set_title(f"{band} at the sensors (not a source localisation)", fontsize=9)
    return f"lowest {band}: {lowest.label} ({float(getattr(lowest, band)):+.2f})" + (
        f"; not OK: {', '.join(bad)}" if bad else ""
    )


def standard_montage_name() -> str:
    """Name of the MNE 10-05 template: ``colin27_1005`` (MNE >= 1.12), else ``standard_1005``."""
    import mne

    names = mne.channels.get_builtin_montages()
    return "colin27_1005" if "colin27_1005" in names else "standard_1005"


if __name__ == "__main__":
    sys.exit(main())
