"""Download the FreeSurfer fsaverage brain and export it for the 3D brain panel.

The download is large (about 760 MB on disk, kept in the data directory for MNE);
the exported mesh is about 1.2 MB. Run with ``--clean`` to delete the download
once the mesh is written.

fsaverage is distributed under the FreeSurfer license: it is **never committed**.
This script downloads it with MNE into the data directory and writes a light mesh
(about 20,000 vertices: the ico-5 subsampling of the pial surface, both
hemispheres) in the frame of the electrode positions (metres):

    $OPENMIND_DATA_DIR/godot/brain_fsaverage.json   (default ~/openmind-data)

Run from the repository root (MNE is only needed here):

    uv run --with "mne>=1.7" --with nibabel python tools/fetch_fsaverage.py

The cockpit uses this file when it exists, and its schematic surface otherwise.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import mne
import numpy as np


def data_dir() -> Path:
    return Path(os.environ.get("OPENMIND_DATA_DIR", Path.home() / "openmind-data")).expanduser()


def main() -> None:
    import argparse
    import shutil

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--clean", action="store_true", help="delete the download afterwards")
    args = parser.parse_args()
    subjects_dir = data_dir() / "freesurfer"
    subjects_dir.mkdir(parents=True, exist_ok=True)
    fs_dir = Path(mne.datasets.fetch_fsaverage(subjects_dir=subjects_dir, verbose=False))

    src = mne.read_source_spaces(fs_dir / "bem" / "fsaverage-ico-5-src.fif", verbose=False)
    vertices: list[np.ndarray] = []
    indices: list[np.ndarray] = []
    offset = 0
    for hemi, space in zip(("lh", "rh"), src, strict=True):
        pial, _ = mne.read_surface(fs_dir / "surf" / f"{hemi}.pial")  # mm, MRI frame
        vertno = space["vertno"]
        remap = np.full(len(pial), -1, dtype=np.int64)
        remap[vertno] = np.arange(len(vertno))
        tris = remap[space["use_tris"]]
        # The MNE 10-05 template positions are given on this same template brain:
        # no transform is needed (checked: electrodes sit 15-27 mm above the
        # cortex all around the head, the thickness of skull and scalp).
        points = pial[vertno] / 1000.0  # metres
        vertices.append(points)
        indices.append(tris + offset)
        offset += len(vertno)

    rr = np.vstack(vertices)
    tris = np.vstack(indices)
    document = {
        "_generated": "by tools/fetch_fsaverage.py from FreeSurfer fsaverage; do not commit",
        "license": "FreeSurfer fsaverage (https://surfer.nmr.mgh.harvard.edu/fswiki/FreeSurferSoftwareLicense)",
        "frame": "fsaverage surface RAS = MNE 10-05 template frame, metres: x right, y front, z up",
        "vertices": [round(float(v), 5) for v in rr.ravel()],
        "indices": [int(i) for i in tris.ravel()],
    }
    target = data_dir() / "godot" / "brain_fsaverage.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(document, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {target}: {len(rr)} vertices, {len(tris)} triangles")
    if args.clean:
        shutil.rmtree(fs_dir)
        print(f"deleted {fs_dir}")


if __name__ == "__main__":
    main()
