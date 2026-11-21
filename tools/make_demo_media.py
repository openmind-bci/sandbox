"""Turn the frames of ``tools/record_demo.gd`` into the README clips.

Clips are animated WebP: full colour, looping, shown by GitHub like an image,
and much lighter than GIF. Each one is kept under the 500 KB limit of the
repository by lowering its quality until it fits. Pillow is only needed here::

    uv run --with pillow python tools/make_demo_media.py /tmp/openmind-frames

Writes ``docs/media/*.webp``. Frames are 1600x900, at 20 fps.
"""

from __future__ import annotations

import argparse
import io
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "docs" / "media"
LIMIT_KB = 480
QUALITIES = (70, 60, 50, 40, 32, 25)
STEP = 3  # keep one frame in three: 20 fps -> 6.7 fps
BRAIN_BOX = (1170, 84, 1580, 432)  # the 3D brain in the right-hand panel

# name: [(scene, first frame, last frame)], width, crop
CLIPS: dict[str, tuple[list[tuple[str, int, int]], int, tuple[int, int, int, int] | None]] = {
    "cockpit-tour": (
        [("robot_twin", 30, 110), ("wheelchair", 150, 230), ("boat", 230, 310), ("bird", 60, 140)],
        640,
        None,
    ),
    "scene-robot-twin": ([("robot_twin", 20, 300)], 560, None),
    "scene-wheelchair": ([("wheelchair", 20, 260)], 560, None),
    "scene-boat": ([("boat", 100, 340)], 560, None),
    "scene-bird": ([("bird", 30, 200)], 560, None),
    "brain-panel": ([("robot_twin", 0, 420)], 300, BRAIN_BOX),
}


def load(
    frames: Path,
    parts: list[tuple[str, int, int]],
    width: int,
    crop: tuple[int, int, int, int] | None,
) -> list[Image.Image]:
    images = []
    for scene, first, last in parts:
        for index in range(first, last, STEP):
            image = Image.open(frames / scene / f"{index:04d}.jpg").convert("RGB")
            if crop is not None:
                image = image.crop(crop)
            height = round(image.height * width / image.width)
            images.append(image.resize((width, height), Image.Resampling.LANCZOS))
    return images


def encode(images: list[Image.Image]) -> tuple[bytes, int]:
    """Highest quality that fits under LIMIT_KB (the lowest one otherwise)."""
    data, quality = b"", QUALITIES[-1]
    for quality in QUALITIES:
        buffer = io.BytesIO()
        images[0].save(
            buffer,
            "WEBP",
            save_all=True,
            append_images=images[1:],
            duration=round(1000 * STEP / 20),
            loop=0,
            quality=quality,
            method=4,
        )
        data = buffer.getvalue()
        if len(data) <= LIMIT_KB * 1024:
            break
    return data, quality


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("frames", type=Path, help="output directory of record_demo.gd")
    parser.add_argument("--only", nargs="*", choices=sorted(CLIPS), help="clips to make")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for name in args.only or CLIPS:
        parts, width, crop = CLIPS[name]
        data, quality = encode(load(args.frames, parts, width, crop))
        (OUT / f"{name}.webp").write_bytes(data)
        status = "" if len(data) <= LIMIT_KB * 1024 else "  ABOVE THE LIMIT"
        print(f"{name}.webp: {len(data) // 1024} KB, quality {quality}{status}")


if __name__ == "__main__":
    main()
