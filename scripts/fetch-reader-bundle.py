#!/usr/bin/env python3
"""Download a verified HTML Reader bundle and print its staging directory.

Stdout is the absolute staging path on success. A failed check exits non-zero
and does not install or restart the reader. See scripts/reader_bundle.py.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import reader_bundle

if __name__ == '__main__':
    sys.exit(reader_bundle.main_fetch())
