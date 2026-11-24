"""Turn downloaded AI clips into frame sequences for build_mock1.py --clips.

Shorts and the map become JPEG frames; mascot clips are green-screen keyed into
RGBA PNGs (alpha from greenness, with green spill suppressed on the edges).
Usage: python3 prepare_clips.py <raw_dir> <out_dir>
"""
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

FPS = 30
raw, out = Path(sys.argv[1]), Path(sys.argv[2])


def key(img):
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = g - np.maximum(r, b)            # how much greener than the other channels
    alpha = np.clip(1 - (green - 40) / 70, 0, 1)
    g2 = np.minimum(g, np.maximum(r, b) + 10)  # spill suppression
    a[..., 1] = np.where(green > 10, g2, g)
    rgba = np.dstack([a, alpha * 255]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


for mp4 in sorted(raw.glob("*.mp4")):
    name = mp4.stem
    d = out / name
    d.mkdir(parents=True, exist_ok=True)
    keyed = name.startswith("mascot_")
    ext = "png" if keyed else "jpg"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(mp4), "-vf", f"fps={FPS}",
                    "-q:v", "2", str(d / f"frame_%05d.{ext}")], check=True)
    if keyed:
        for f in sorted(d.glob("frame_*.png")):
            key(Image.open(f)).save(f)
    print(name, len(list(d.glob("frame_*"))))
