# Assets and credits

Graphic, 3D and sound assets used in this repository, with their origin and
license. Only **CC0** or explicitly compatible free licenses are accepted, and
only original designs: no character, vehicle or logo from a protected work.

Heavy binary files (`*.glb`, `*.png`, `*.jpg`, `*.hdr`, `*.exr`, `*.wav`, `*.ogg`) are stored
with Git LFS. Poly Haven assets are downloaded by `tools/fetch_polyhaven.py` (1K
resolution, to stay light).

| File or folder | Author / source | License | Notes |
|---|---|---|---|
| `godot/assets/polyhaven/concrete_floor_worn_001/` | Concrete Floor Worn 001 by Dimitrios Savva, Rico Cilliers, [Poly Haven](https://polyhaven.com/a/concrete_floor_worn_001) | CC0 | robot twin floor |
| `godot/assets/polyhaven/plastered_wall_04/` | Plastered Wall 04 by Rob Tuytel, [Poly Haven](https://polyhaven.com/a/plastered_wall_04) | CC0 | robot twin walls |
| `godot/assets/polyhaven/brown_planks_09/` | Brown Planks 09 by Rob Tuytel, [Poly Haven](https://polyhaven.com/a/brown_planks_09) | CC0 | robot twin obstacles |
| `godot/assets/polyhaven/laminate_floor_02/` | Laminate Floor 02 by Dario Barresi, Charlotte Baglioni, [Poly Haven](https://polyhaven.com/a/laminate_floor_02) | CC0 | wheelchair floor |
| `godot/assets/polyhaven/white_plaster_02/` | White Plaster 02 by Rob Tuytel, [Poly Haven](https://polyhaven.com/a/white_plaster_02) | CC0 | wheelchair walls |
| `godot/assets/polyhaven/wood_planks_grey/` | Wood Planks Grey by Rob Tuytel, [Poly Haven](https://polyhaven.com/a/wood_planks_grey) | CC0 | wheelchair doors |
| `godot/assets/polyhaven/small_empty_room_3/` | Small Empty Room 3 by Sergej Majboroda, [Poly Haven](https://polyhaven.com/a/small_empty_room_3) | CC0 | robot twin and wheelchair lighting |
| `godot/addons/openmind/fonts/SpaceGrotesk.ttf` | Florian Karsten, [Space Grotesk](https://github.com/floriankarsten/space-grotesk) (via Google Fonts) | SIL Open Font License 1.1 (`fonts/OFL.txt`) | variable font |

The 3D panel shows the FreeSurfer fsaverage brain, downloaded on each machine by
`tools/fetch_fsaverage.py` under the FreeSurfer license (never committed); without
it, a schematic surface generated in code (`godot/panels/brain/brain_mesh.gd`, an
original shape, not an asset).

Assets that cannot be redistributed (for example the FreeSurfer `fsaverage`
cortex mesh) are **downloaded by a script** and never committed.
