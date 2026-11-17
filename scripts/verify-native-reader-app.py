#!/usr/bin/env python3
"""Verify signed app/delivery integrity; report final application gates separately."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_app_package', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec); spec.loader.exec_module(package)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--binding', type=Path, help='Required exact input binding when checking a candidate')
    parser.add_argument('--source-revision', help='Expected current application revision; rejects a valid but stale app')
    parser.add_argument('--require-delivery', action='store_true')
    parser.add_argument('--acceptance', action='store_true', help='Fail nonzero for pending final core/page/GUI/OS13 gates')
    args = parser.parse_args()
    try:
        manifest = package.validate(args.app)
        if args.source_revision and manifest['sourceRevision'] != args.source_revision:
            raise ValueError('Stale application sourceRevision')
        delivery = args.app / 'Contents/Resources/native-reader'
        if not manifest.get('nativeDeliverySHA256'):
            if args.require_delivery:
                raise ValueError('Required portable delivery missing')
            code = 2
            report = {'status':'runtime-delivery-blocked', 'diagnostics':['Portable delivery payload absent.']}
        else:
            payload = package.delivery_module().verify(delivery, json.loads(args.binding.read_text()) if args.binding else None)
            code = 2 if args.acceptance else 0
            report = {'status':'final-acceptance-blocked' if args.acceptance else 'delivery-integrity-verified',
                      'payloadSHA256':payload['payloadSHA256'], 'helperSHA256':payload['helperSHA256'],
                      'signing':payload['signing'], 'capabilities':payload['capabilities'],
                      'diagnostics':['Initial delivery only: final NA06/core and NA12/original-page binding remains pending.',
                                     'Current-host integrity does not certify GUI/VoiceOver, live chat/account or macOS13 execution.']}
        report.update(app=str(args.app.resolve()), integrity='verified', sourceRevision=manifest['sourceRevision'],
                      sourceDirty=manifest['sourceDirty'], bundleChecksum=package.bundle_checksum(args.app),
                      engineInputSHA256=manifest['engineInputSHA256'], engineSHA256=manifest['engineSHA256'], exit=code)
    except Exception as error:
        report = dict(app=str(args.app), integrity='failed', exit=1, diagnostic=str(error)); code = 1
    if args.output:
        package.write_json(args.output, report)
    print(json.dumps(report, indent=2)); return code


if __name__ == '__main__':
    sys.exit(main())
