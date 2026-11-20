"""Download the Poly Haven assets of the Godot scenes (all CC0).

Textures (1K JPG: colour, OpenGL normal, roughness) and HDRI skies (1K HDR) go to
``godot/assets/polyhaven/<id>/``; they are committed through Git LFS and credited
in ASSETS.md. Run again after changing the lists below:

    uv run python tools/fetch_polyhaven.py

Poly Haven (https://polyhaven.com) publishes every asset under CC0.
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

#: Texture id -> where it is used.
TEXTURES = {
    "concrete_floor_worn_001": "robot twin floor",
    "plastered_wall_04": "robot twin walls",
    "brown_planks_09": "robot twin obstacles",
    "laminate_floor_02": "wheelchair floor",
    "white_plaster_02": "wheelchair walls",
    "wood_planks_grey": "wheelchair doors",
}
#: HDRI id -> where it is used.
HDRIS = {
    "small_empty_room_3": "robot twin and wheelchair lighting",
}
MAPS = {"Diffuse": "diff", "nor_gl": "nor_gl", "Rough": "rough"}
API = "https://api.polyhaven.com"
TARGET = Path("godot/assets/polyhaven")
USER_AGENT = "openmind-sandbox-asset-fetch"


def get_json(url: str) -> dict[str, object]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        data: dict[str, object] = json.load(response)
        return data


def download(url: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        path.write_bytes(response.read())
    print(f"  {path} ({path.stat().st_size // 1024} kB)")


def main() -> int:
    credits = []
    for asset_id, use in {**TEXTURES, **HDRIS}.items():
        info = get_json(f"{API}/info/{asset_id}")
        files = get_json(f"{API}/files/{asset_id}")
        print(asset_id)
        if asset_id in HDRIS:
            hdri = files["hdri"]["1k"]["hdr"]  # type: ignore[index]
            download(hdri["url"], TARGET / asset_id / f"{asset_id}_1k.hdr")
        else:
            for key, suffix in MAPS.items():
                jpg = files[key]["1k"]["jpg"]  # type: ignore[index]
                download(jpg["url"], TARGET / asset_id / f"{asset_id}_{suffix}_1k.jpg")
        authors = ", ".join(info.get("authors", {}))  # type: ignore[arg-type]
        credits.append(
            f"| `godot/assets/polyhaven/{asset_id}/` | {info['name']} by {authors}, "
            f"[Poly Haven](https://polyhaven.com/a/{asset_id}) | CC0 | {use} |"
        )
    print("\nASSETS.md rows:")
    print("\n".join(credits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
