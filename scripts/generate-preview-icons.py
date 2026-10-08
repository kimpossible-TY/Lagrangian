#!/usr/bin/env python3
"""Regenerate browser icons from the Flow app icon on macOS."""
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/tinymist-flow.png'
OUTPUT = ROOT / 'tools/typst-preview-frontend/public'


def resize(size, destination):
    subprocess.run(['/usr/bin/sips', '-z', str(size), str(size), str(SOURCE),
                    '--out', str(destination)], check=True, stdout=subprocess.DEVNULL)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    resize(64, OUTPUT / 'favicon.png')
    resize(180, OUTPUT / 'apple-touch-icon.png')
    sizes = (16, 32, 48, 64)
    images = []
    with tempfile.TemporaryDirectory() as temporary:
        for size in sizes:
            path = Path(temporary) / f'{size}.png'
            resize(size, path)
            images.append(path.read_bytes())
    offset = 6 + 16 * len(images)
    entries = []
    for size, data in zip(sizes, images):
        entries.append(struct.pack('<BBBBHHII', size, size, 0, 0, 1, 32, len(data), offset))
        offset += len(data)
    (OUTPUT / 'favicon.ico').write_bytes(
        struct.pack('<HHH', 0, 1, len(images)) + b''.join(entries) + b''.join(images))


if __name__ == '__main__':
    main()
