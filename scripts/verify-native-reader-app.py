#!/usr/bin/env python3
"""Verify dev app integrity, then report outstanding native runtime delivery gates (exit 2)."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_app_package', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        manifest = package.validate(args.app)
        report = dict(app=str(args.app.resolve()), integrity='verified',
                      sourceRevision=manifest['sourceRevision'], sourceDirty=manifest['sourceDirty'],
                      bundleChecksum=package.bundle_checksum(args.app),
                      engineInputSHA256=manifest['engineInputSHA256'], engineSHA256=manifest['engineSHA256'],
                      exit=2, status='runtime-delivery-blocked',
                      diagnostics=['NA08 production runtime/payload contract is not yet supplied; scratch runtimes are test inputs only.',
                                   'Shared image contract correction, TeX answer math and original PDF server publication remain pending.',
                                   'This dev app is not standalone/installable/full F04/F01–18 acceptance.'])
        code = 2
    except Exception as error:
        report = dict(app=str(args.app), integrity='failed', exit=1, diagnostic=str(error))
        code = 1
    if args.output:
        package.write_json(args.output, report)
    print(json.dumps(report, indent=2))
    return code


if __name__ == '__main__':
    sys.exit(main())
