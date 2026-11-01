#!/usr/bin/env python3
"""Package the HTML Reader bundle for the flow-engine workflow."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import reader_bundle

if __name__ == '__main__':
    sys.exit(reader_bundle.main_package())
