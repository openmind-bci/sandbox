# Live 3D brain panel

The **3D brain** panel of the [cockpit](cockpit.md) colours a brain surface with
the band power messages (`openmind/v1/bandpower`, about 10 Hz).

> **Activity estimated at the sensors — this is not a source localisation.**
> Each point of the surface shows a distance-weighted mean of the electrodes
> around it. It tells *which electrodes* change, not where in the brain the
> activity comes from.

## Reading it

The surface is drawn like a functional scan: a grey cortex (its folds stay
visible) with coloured blobs where the band power changes.

| Colour | Meaning |
|---|---|
| grey cortex | no notable change (below 12 % of the scale) |
| blue → cyan → green → yellow → red | strength of the change at the sensors, from weak to strong (absolute value of `rel_mu` or `rel_beta`, full red at 0.4) |
| dark grey | electrode reported `ok: false` (absent, flat or saturated) |

The colour shows the **strength** of the change, not its direction: imagining a
movement lowers mu (desynchronization), a jaw clench raises beta, and both light
up. Imagining the left hand should light the area of **C4**, the right hand
**C3**, both feet **Cz / CPz**.

Controls: drag to rotate, **Top / Left / Right** views, **mu / beta** band,
**Electrodes** to show their positions and names, **Enlarge ⤢** to open the same
brain in a large, resizable window (drag to rotate there too). Colours move smoothly
(time constant 0.25 s).

## Test sources, no headset needed

0. the **demo mode** of the cockpit (Start demo, Ctrl+D), with nothing else running;
1. Fake messages from the keyboard simulator (display only):
   `openmind-sandbox keys --bandpower` (add `--bad-channel CPz` to see a grey area);
2. the synthetic source of OpenMind Plug with `openmind-core bandpower` (whole
   chain, known answer);
3. a public recording replayed by Plug with `openmind-core bandpower` (real,
   noisier activity).

## 2D check

When in doubt, compare with a classic topographic map drawn by MNE from the same
messages (same colours and scale; electrodes not OK are grey crosses):

```bash
uv run --with "mne>=1.7" --with matplotlib python tools/check_topomap.py
uv run --with "mne>=1.7" --with matplotlib python tools/check_topomap.py --once --output map.png
```

It also prints the electrode with the lowest value (`lowest rel_mu: C4 (-0.43)`):
the same area must turn blue in the 3D panel.

## Brain surface: fsaverage

The panel shows the FreeSurfer **fsaverage** brain when it has been exported on
this machine, and a schematic surface otherwise (for example in CI). fsaverage is
distributed under the [FreeSurfer license](https://surfer.nmr.mgh.harvard.edu/fswiki/FreeSurferSoftwareLicense):
it is **downloaded by a script and never committed**.

```bash
uv run --with "mne>=1.7" --with nibabel python tools/fetch_fsaverage.py
uv run --with "mne>=1.7" --with nibabel python tools/fetch_fsaverage.py --clean
```

The script downloads fsaverage with MNE into `$OPENMIND_DATA_DIR/freesurfer/`
(about **760 MB** on disk) and writes a light mesh,
`$OPENMIND_DATA_DIR/godot/brain_fsaverage.json` (about 1.2 MB: the ico-5
subsampling of the pial surface, 20,484 vertices). `--clean` deletes the download
once the mesh is written. `OPENMIND_DATA_DIR` defaults to `~/openmind-data`; the
cockpit reads the same variable.

The 10-05 electrode template of MNE is defined on this same brain, so no
transform is needed: the electrodes sit 15 to 27 mm above the cortex all around
the head (skull and scalp).

## How it is built

- **Brain surface**: fsaverage as above, or the schematic shape generated in code
  (`godot/panels/brain/brain_mesh.gd`: two folded hemispheres and a fissure, an
  original drawing). Normals are computed once and turned outwards whatever the
  winding of the source.
- **Electrode positions**: `godot/data/electrodes_10_10.json`, generated from the
  MNE 10-05 template montage (`colin27_1005`, formerly `standard_1005`) by `tools/generate_electrodes.py`
  (`uv run --with "mne>=1.7" python tools/generate_electrodes.py`). Positions are
  in the MNE head frame and match OpenMind Plug.
- **Colouring** (`brain_colors.gd`): Gaussian weights (σ = 30 mm) from every
  electrode of the message to every vertex, precomputed once per montage and kept
  only above 1 % (about 3 ms per update for fsaverage); the surface is
  recoloured at most 20 times per second.
