"""Generate godot/data/electrodes_10_10.json from the MNE 10-05 template montage.

Run from the repository root (MNE is only needed for this script):

    uv run --with "mne>=1.7" python tools/generate_electrodes.py

Positions are in the MNE head frame, in metres: x to the right, y to the front
(nasion), z up. Only the 10-10 electrodes are kept.
"""

from __future__ import annotations

import json
from pathlib import Path

import mne

#: The 10-10 system (as used by OpenMind Plug montages), plus mastoids.
LABELS_10_10 = """
Fp1 Fpz Fp2 AF7 AF3 AFz AF4 AF8 F9 F7 F5 F3 F1 Fz F2 F4 F6 F8 F10
FT9 FT7 FC5 FC3 FC1 FCz FC2 FC4 FC6 FT8 FT10 T9 T7 C5 C3 C1 Cz C2 C4 C6 T8 T10
TP9 TP7 CP5 CP3 CP1 CPz CP2 CP4 CP6 TP8 TP10 P9 P7 P5 P3 P1 Pz P2 P4 P6 P8 P10
PO7 PO3 POz PO4 PO8 O1 Oz O2 Iz
""".split()  # noqa: SIM905 - one readable line per row of the 10-10 grid


def standard_montage_name() -> str:
    """Name of the MNE 10-05 template: ``colin27_1005`` (MNE >= 1.12), else ``standard_1005``."""
    import mne

    names = mne.channels.get_builtin_montages()
    return "colin27_1005" if "colin27_1005" in names else "standard_1005"


def main() -> None:
    montage = mne.channels.make_standard_montage(standard_montage_name())
    positions = montage.get_positions()["ch_pos"]
    electrodes = {
        label: [round(float(v), 5) for v in positions[label]]
        for label in LABELS_10_10
        if label in positions
    }
    document = {
        "_generated": "by tools/generate_electrodes.py (MNE 10-05 template); do not edit",
        "frame": "MNE head frame, metres: x right, y front, z up",
        "electrodes": electrodes,
    }
    target = Path("godot/data/electrodes_10_10.json")
    target.write_text(json.dumps(document, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {target} ({len(electrodes)} electrodes)")


if __name__ == "__main__":
    main()
