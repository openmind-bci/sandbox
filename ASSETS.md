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
| `godot/assets/polyhaven/fabric_pattern_07/` | Fabric Pattern 07 by Rob Tuytel, [Poly Haven](https://polyhaven.com/a/fabric_pattern_07) | CC0 | wheelchair furniture |
| `godot/assets/polyhaven/aerial_grass_rock/` | Aerial Grass Rock by Rob Tuytel, [Poly Haven](https://polyhaven.com/a/aerial_grass_rock) | CC0 | bird landscape |
| `godot/assets/polyhaven/brown_planks_03/` | Brown Planks 03 by Rob Tuytel, [Poly Haven](https://polyhaven.com/a/brown_planks_03) | CC0 | boat deck |
| `godot/assets/polyhaven/kloofendal_48d_partly_cloudy_puresky/` | Kloofendal 48d Partly Cloudy (Pure Sky) by Greg Zaal, Jarod Guest, [Poly Haven](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky) | CC0 | bird and boat sky |
| `godot/assets/polyhaven/wheelchair_01/` | Wheelchair 01 by Garreth Dean, [Poly Haven](https://polyhaven.com/a/wheelchair_01) | CC0 | wheelchair (scanned model) |
| `godot/assets/polyhaven/sofa_03/` | Sofa 03 by Fran Calvente, [Poly Haven](https://polyhaven.com/a/sofa_03) | CC0 | wheelchair living room |
| `godot/assets/polyhaven/coffee_table_round_01/` | Coffee Table Round 01 by Ulan Cabanilla, [Poly Haven](https://polyhaven.com/a/coffee_table_round_01) | CC0 | wheelchair living room |
| `godot/assets/polyhaven/vintage_day_bed/` | Vintage Day Bed by Aron Łyczek, [Poly Haven](https://polyhaven.com/a/vintage_day_bed) | CC0 | wheelchair bedroom |
| `godot/assets/polyhaven/painted_wooden_nightstand/` | Painted Wooden Nightstand by Kirill Sannikov, [Poly Haven](https://polyhaven.com/a/painted_wooden_nightstand) | CC0 | wheelchair bedroom |
| `godot/assets/polyhaven/potted_plant_02/` | Potted Plant 02 by Rico Cilliers, [Poly Haven](https://polyhaven.com/a/potted_plant_02) | CC0 | wheelchair living room |
| `godot/assets/polyhaven/Barrel_01/` | Barrel 01 by Jorge Camacho, [Poly Haven](https://polyhaven.com/a/Barrel_01) | CC0 | robot twin obstacles |
| `godot/assets/polyhaven/ocean_buoy/` | Ocean Buoy by Mateusz Sadek, [Poly Haven](https://polyhaven.com/a/ocean_buoy) | CC0 | boat buoys |
| `godot/assets/polyhaven/lifebuoy/` | Lifebuoy by Hank Kaamura, [Poly Haven](https://polyhaven.com/a/lifebuoy) | CC0 | boat deck |
| `godot/assets/models/quaternius/UAL1_Standard.glb` | Universal Animation Library (Standard) by Quaternius, [quaternius.com](https://quaternius.com/packs/universalanimationlibrary.html) (downloaded by hand; licence file in the pack): its neutral mannequin and "Sitting_Idle" animation | CC0 | person seated in the wheelchair |
| `godot/assets/models/sailing_yacht/` | Sailing yacht, 8 m by Innerscene Corp, [Innerscene 3D parts library](https://www.innerscene.com/tools/library/3d-parts/sailing-yacht-8-m-aa9dbd30) (downloaded by hand from the page; the licence is also embedded in the file) | CC0 | boat |
| `godot/assets/models/sail_boat/` | Sail Boat by Quaternius, [Poly Pizza](https://poly.pizza/m/BgSZXwmm7k) | CC0 | boat (fallback) |
| `godot/assets/models/shrike/` | Bird (Yellow-Billed Shrike) by pistachio, [OpenGameArt](https://opengameart.org/content/bird-yellow-billed-shrike); converted to GLB and textures reduced to 1K by `tools/fetch_models.py` | CC0 | calibration bird |
| `godot/assets/models/pigeon/` | Low poly 3D pigeon (rigged, animated) by mujtaba-io, [OpenGameArt](https://opengameart.org/content/low-poly-3d-pigeon-model-rigged-animated-untextured); converted to GLB with Blender by `tools/fetch_models.py` | CC0 | calibration bird (fallback) |
| `godot/addons/openmind/fonts/SpaceGrotesk.ttf` | Florian Karsten, [Space Grotesk](https://github.com/floriankarsten/space-grotesk) (via Google Fonts) | SIL Open Font License 1.1 (`fonts/OFL.txt`) | variable font |

The 3D panel shows the FreeSurfer fsaverage brain, downloaded on each machine by
`tools/fetch_fsaverage.py` under the FreeSurfer license (never committed); without
it, a schematic surface generated in code (`godot/panels/brain/brain_mesh.gd`, an
original shape, not an asset).

Assets that cannot be redistributed (for example the FreeSurfer `fsaverage`
cortex mesh) are **downloaded by a script** and never committed.
