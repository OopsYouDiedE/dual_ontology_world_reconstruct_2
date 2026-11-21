"""Place the four project schematic figures in the empty Godot comparison columns."""
import argparse
import json
from pathlib import Path

from PIL import Image

# Reference name, crown and sole rows, midline column in the 1024x1536 source.
REFERENCES = {
    "detective": ("detective-bald-front-fit.png", 54, 1445, 510),
    "halvard": ("halvard-bald-front-v1.png", 43, 1463, 508),
    "jane": ("jane-cox-natural-front-v3.png", 16, 1448, 511),
    "qingyue": ("ruan-qingyue-bald-front-v1.png", 47, 1466, 510),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fit_output", type=Path)
    parser.add_argument("reference_dir", type=Path)
    args = parser.parse_args()
    receipt = json.loads((args.fit_output / "fit-receipt.json").read_text(encoding="utf-8"))
    canvas = Image.open(args.fit_output / "godot/01-front.png").convert("RGB")
    w, h = canvas.width // 2, canvas.height // 2
    # Same orthographic height and camera center as MuscleReview.gd.
    pixels_per_m = h / 2.22
    sole_y = round(h / 2 + 0.95 * pixels_per_m)
    for i, (name, (image, crown, sole, midline)) in enumerate(REFERENCES.items()):
        with Image.open(args.reference_dir / image) as source:
            assert source.size == (1024, 1536), source.size
            target_height = receipt["cast"][name]["review_height_m"] * pixels_per_m
            scale = target_height / (sole - crown)
            radius = min(midline, source.width - midline, int(w * 0.15 / scale))
            margin = 9
            crop = source.convert("RGB").crop((midline - radius, crown - margin,
                                               midline + radius, sole + margin))
            tile = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.LANCZOS)
        x = (i % 2) * w + (w // 3 - tile.width) // 2
        y = (i // 2) * h + sole_y - round((sole + margin - crown) * scale)
        canvas.paste(tile, (x, y))
    canvas.save(args.fit_output / "00-design-comparison.jpg", quality=95, subsampling=0)


if __name__ == "__main__":
    main()
