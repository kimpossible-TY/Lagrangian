#!/usr/bin/env python3
"""Regenerate Reader browser icons from the Flow branding PNG (requires Pillow).

Run `python3 tools/flow-reader/generate-icons.py` from the repository checkout.
The web icons are generated artifacts; edit assets/branding/tinymist-flow.png
to change their artwork.
"""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
WEB = Path(__file__).resolve().parent / "web"


def main():
    with Image.open(ROOT / "assets/branding/tinymist-flow.png") as source:
        source = source.convert("RGBA")
        source.resize((64, 64), Image.Resampling.LANCZOS).save(WEB / "favicon.png")
        source.save(WEB / "favicon.ico", format="ICO",
                    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64)])
        # iOS supplies its own corner mask; provide opaque pixels underneath it.
        touch = Image.new("RGB", (180, 180), "#15136e")
        resized = source.resize(touch.size, Image.Resampling.LANCZOS)
        touch.paste(resized, mask=resized.getchannel("A"))
        touch.save(WEB / "apple-touch-icon.png")
        for size in (192, 512):
            icon = Image.new("RGB", (size, size), "#15136e")
            resized = source.resize(icon.size, Image.Resampling.LANCZOS)
            icon.paste(resized, mask=resized.getchannel("A"))
            icon.save(WEB / f"app-icon-{size}.png")


if __name__ == "__main__":
    main()
