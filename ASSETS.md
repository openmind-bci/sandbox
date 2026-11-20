# Assets and credits

Graphic, 3D and sound assets used in this repository, with their origin and
license. Only **CC0** or explicitly compatible free licenses are accepted, and
only original designs: no character, vehicle or logo from a protected work.

Heavy binary files (`*.glb`, `*.png`, `*.wav`, `*.ogg`) are stored with Git LFS.

| File or folder | Author / source | License | Notes |
|---|---|---|---|
| `godot/addons/openmind/fonts/SpaceGrotesk.ttf` | Florian Karsten, [Space Grotesk](https://github.com/floriankarsten/space-grotesk) (via Google Fonts) | SIL Open Font License 1.1 (`fonts/OFL.txt`) | variable font |

The brain surface of the 3D panel is generated in code (`godot/panels/brain/brain_mesh.gd`):
an original schematic shape, not an asset.

Assets that cannot be redistributed (for example the FreeSurfer `fsaverage`
cortex mesh) are **downloaded by a script** and never committed.
