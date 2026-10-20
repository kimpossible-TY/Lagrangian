"""Run Reader service tests, optionally requiring complete integration coverage."""

import argparse
import os
from pathlib import Path
import sys
import unittest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-integration", action="store_true")
    args = parser.parse_args()
    if args.require_integration:
        packages = os.environ.get("FLOW_READER_PACKAGES")
        if not packages or not Path(packages).is_dir():
            parser.error("FLOW_READER_PACKAGES must name an existing package directory")

    root = Path(__file__).resolve().parents[1]
    suite = unittest.defaultTestLoader.discover(str(root / "tools/flow-reader/tests"))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if args.require_integration and result.skipped:
        print("Required Reader integration coverage was skipped:", file=sys.stderr)
        for test, reason in result.skipped:
            print(f"  {test}: {reason}", file=sys.stderr)
        return 1
    return 0 if result.wasSuccessful() and result.testsRun else 1


if __name__ == "__main__":
    sys.exit(main())
