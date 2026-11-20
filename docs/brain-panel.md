# Live 3D brain panel

The **3D brain** panel of the [cockpit](cockpit.md) colours a brain surface with
the band power messages (`openmind/v1/bandpower`, about 10 Hz).

> **Activity estimated at the sensors — this is not a source localisation.**
> Each point of the surface shows a distance-weighted mean of the electrodes
> around it. It tells *which electrodes* change, not where in the brain the
> activity comes from.

## Reading it

| Colour | Meaning |
|---|---|
| blue | `rel_mu` (or `rel_beta`) below the resting baseline: desynchronization, expected over the motor area of an imagined movement |
| light | no change |
| orange | above the baseline (for example beta during a jaw clench) |
| grey | electrode reported `ok: false` (absent, flat or saturated) |
| dark blue-grey | no electrode nearby |

The scale is diverging and saturates at ±0.5. Imagining the left hand should turn
the area of **C4** blue, the right hand **C3**, both feet **Cz / CPz**.

Controls: drag to rotate, **Top / Left / Right** views, **mu / beta** band,
**Electrodes** to show their positions and names. Colours move smoothly
(time constant 0.25 s).

## Test sources, no headset needed

1. Fake messages from the keyboard simulator (display only):
   `openmind-sandbox keys --bandpower` (add `--bad-channel CPz` to see a grey area);
2. the synthetic source of OpenMind Plug with `openmind-core bandpower` (whole
   chain, known answer);
3. a public recording replayed by Plug with `openmind-core bandpower` (real,
   noisier activity).

## How it is built

- **Brain surface**: a schematic shape generated in code
  (`godot/panels/brain/brain_mesh.gd`: two folded hemispheres and a fissure).
  It is an original drawing, not an anatomical model: nothing to download and no
  license to track. An anatomical mesh (for example FreeSurfer `fsaverage`,
  which must be downloaded by script and never committed) can replace it later.
- **Electrode positions**: `godot/data/electrodes_10_10.json`, generated from the
  MNE `standard_1005` montage by `tools/generate_electrodes.py`
  (`uv run --with "mne>=1.7" python tools/generate_electrodes.py`). Positions are
  in the MNE head frame and match OpenMind Plug.
- **Colouring** (`brain_colors.gd`): Gaussian weights (σ = 24 mm) from every
  electrode of the message to every vertex, precomputed once per montage.
