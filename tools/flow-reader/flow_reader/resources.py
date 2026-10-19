"""Locate immutable Reader resources in source and installed releases."""
from pathlib import Path

READER_ROOT = Path(__file__).resolve().parents[1]
SHARED_ROOT = READER_ROOT.parent / "reader-common"
