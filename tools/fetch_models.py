"""Download the CC0 models that do not come from Poly Haven.

- Sail Boat by Quaternius (CC0), from Poly Pizza, as GLB;
- Pigeon by mujtaba-io (CC0), from OpenGameArt, as a .blend file converted to
  GLB with Blender (only the bird and its armature, with its animations);
- Yellow-billed shrike by pistachio (CC0), from OpenGameArt, a textured bird in flight
  (996 triangles, rigged), converted to GLB with Blender; its 2K textures are
  reduced to 1K PNG (the colour map keeps its alpha for the feathers).

Files go to ``godot/assets/models/<name>/`` (Git LFS) and are credited in
ASSETS.md. Blender must be installed for the pigeon (``blender`` on PATH):

    uv run python tools/fetch_models.py

The .blend file is opened with Python scripts disabled (``--disable-autoexec``).
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

TARGET = Path("godot/assets/models")
USER_AGENT = "openmind-sandbox-asset-fetch"
SAIL_BOAT = "https://static.poly.pizza/b1d42c7e-152a-4d56-a754-cca000a5abad.glb"
SHRIKE_ZIP = "https://opengameart.org/sites/default/files/bird_yellow_billed_shrike.zip"
SHRIKE_SCRIPT = """
import bpy, sys
from pathlib import Path
out = Path(sys.argv[sys.argv.index("--") + 1])
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.data.objects:
    if o.type in ("MESH", "ARMATURE"):
        o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(out / "shrike.glb"), export_format="GLB",
                          use_selection=True, export_animations=False)
for name in ("diff", "norm", "rgh"):
    image = bpy.data.images["bird_shrike1_" + name]
    if image.size[0] > 1024:
        image.scale(1024, 1024)
    image.filepath_raw = str(out / f"shrike_{name}.png")
    image.file_format = "PNG"
    image.save()
"""
PIGEON_BLEND = (
    "https://opengameart.org/sites/default/files/genuinely-my-pigeon-extended-furthur.blend"
)
EXPORT_SCRIPT = """
import bpy, sys
out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.object.select_all(action="DESELECT")
for name in ("pigeon-model", "pigeon-armature"):
    bpy.data.objects[name].select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True,
                          export_animations=True, export_animation_mode="ACTIONS")
"""


def download(url: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        path.write_bytes(response.read())
    print(f"  {path} ({path.stat().st_size // 1024} kB)")


def main() -> int:
    print("sail boat (Quaternius, CC0)")
    download(SAIL_BOAT, TARGET / "sail_boat" / "sail_boat.glb")
    print("pigeon (mujtaba-io, CC0)")
    blender = shutil.which("blender")
    if blender is None:
        print("  Blender not found: pigeon skipped", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory() as work:
        blend = Path(work) / "pigeon.blend"
        script = Path(work) / "export.py"
        download(PIGEON_BLEND, blend)
        script.write_text(EXPORT_SCRIPT, encoding="utf-8")
        out = (TARGET / "pigeon" / "pigeon.glb").resolve()
        out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [blender, "--background", "--factory-startup", "--disable-autoexec", str(blend),
             "--python", str(script), "--", str(out)],
            check=True, capture_output=True, cwd=work,
        )  # fmt: skip
        print(f"  {out.relative_to(Path.cwd())} ({out.stat().st_size // 1024} kB)")
    print("shrike (OpenGameArt, CC0)")
    with tempfile.TemporaryDirectory() as work:
        archive = Path(work) / "shrike.zip"
        download(SHRIKE_ZIP, archive)
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(work)
        script = Path(work) / "export.py"
        script.write_text(SHRIKE_SCRIPT, encoding="utf-8")
        out_dir = (TARGET / "shrike").resolve()
        out_dir.mkdir(parents=True, exist_ok=True)
        blend = Path(work) / "bird_yellow_billed_shrike" / "bird_shrike1.blend"
        subprocess.run(
            [blender, "--background", "--factory-startup", "--disable-autoexec", str(blend),
             "--python", str(script), "--", str(out_dir)],
            check=True, capture_output=True, cwd=work,
        )  # fmt: skip
        for path in sorted(out_dir.iterdir()):
            print(f"  {path.relative_to(Path.cwd())} ({path.stat().st_size // 1024} kB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
