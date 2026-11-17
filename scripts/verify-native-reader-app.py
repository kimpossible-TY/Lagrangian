#!/usr/bin/env python3
"""Verify signed app/delivery integrity; report final application gates separately."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_app_package', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec); spec.loader.exec_module(package)

GATES = ('source', 'runtime', 'requiredtests', 'code-review', 'docs', 'nativeGUI', 'AX')


def acceptance_receipt(path, source_revision, bundle_checksum):
    """Check an external PM decision record, not reviewer quality or authority."""
    def require(value, message):
        if not value:
            raise ValueError(message)

    def bounded_json(file, limit):
        with file.open('rb') as stream:
            data = stream.read(limit + 1)
        require(len(data) <= limit, 'Oversized PM evidence')
        return data, json.loads(data)

    require(path is not None, 'External PM acceptance receipt missing')
    path = Path(path).resolve(strict=True)
    receipt_bytes, receipt = bounded_json(path, 65536)
    require(type(receipt.get('schemaVersion')) is int and receipt['schemaVersion'] == 1
            and receipt.get('kind') == 'external-pm-acceptance'
            and receipt.get('decision') == 'accepted'
            and isinstance(receipt.get('recordedBy'), str) and receipt['recordedBy'].strip(),
            'Invalid external PM decision')
    require(receipt.get('sourceRevision') == source_revision
            and receipt.get('bundleChecksum') == bundle_checksum, 'Stale PM app/source binding')
    gates = receipt.get('gates')
    require(isinstance(gates, dict) and set(gates) == set(GATES), 'Missing or unknown PM gates')
    verified = {}
    for name in GATES:
        gate = gates[name]
        require(isinstance(gate, dict) and gate.get('status') == 'passed', 'Unpassed PM gate: ' + name)
        relative = gate.get('artifact')
        require(isinstance(relative, str) and relative and not Path(relative).is_absolute()
                and '\\' not in relative and all(p not in ('', '.', '..') for p in relative.split('/')),
                'Invalid PM artifact path: ' + name)
        artifact = (path.parent / relative).resolve(strict=True)
        require(artifact.is_relative_to(path.parent), 'PM artifact escapes receipt directory')
        data, evidence = bounded_json(artifact, 1024 * 1024)
        digest = hashlib.sha256(data).hexdigest()
        require(digest == gate.get('sha256'), 'PM artifact digest mismatch: ' + name)
        require(evidence.get('gate') == name and evidence.get('status') == 'passed'
                and evidence.get('sourceRevision') == source_revision
                and evidence.get('bundleChecksum') == bundle_checksum, 'Stale or failed PM artifact: ' + name)
        require(type(evidence.get('requiredSkips')) is int and evidence['requiredSkips'] == 0,
                'Required skip or missing skip count: ' + name)
        if name == 'requiredtests':
            require(type(evidence.get('tests')) is int and evidence['tests'] > 0, 'Required tests absent')
        verified[name] = {'artifact':relative, 'sha256':digest, 'status':'passed'}
    return {'receipt':str(path), 'sha256':hashlib.sha256(receipt_bytes).hexdigest(), 'recordedBy':receipt['recordedBy'],
            'gates':verified, 'meaning':'External PM decision record; does not authenticate authority or review quality.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--binding', type=Path, help='Required exact input binding when checking a candidate')
    parser.add_argument('--source-revision', help='Expected current application revision; rejects a valid but stale app')
    parser.add_argument('--require-delivery', action='store_true')
    parser.add_argument('--acceptance', action='store_true', help='Require an app/source-bound external PM decision receipt')
    parser.add_argument('--pm-acceptance-receipt', type=Path, help='External PM receipt; no effect on normal app launch')
    args = parser.parse_args()
    if args.pm_acceptance_receipt and not args.acceptance:
        parser.error('--pm-acceptance-receipt requires --acceptance')
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
            code = 0
            report = {'status':'delivery-integrity-verified',
                      'payloadSHA256':payload['payloadSHA256'], 'helperSHA256':payload['helperSHA256'],
                      'signing':payload['signing'], 'capabilities':payload['capabilities'],
                      'diagnostics':['Integration capabilities and exact source binding are recorded in the payload.',
                                     'Current-host/minOS inspection does not certify macOS13 execution, live provider use or VoiceOver speech.']}
            if args.acceptance:
                try:
                    report['pmAcceptance'] = acceptance_receipt(args.pm_acceptance_receipt,
                        manifest['sourceRevision'], package.bundle_checksum(args.app))
                    report['status'] = 'pm-acceptance-recorded'
                except (ValueError, OSError, TypeError, KeyError, AttributeError) as error:
                    code = 2
                    report.update(status='final-acceptance-blocked', acceptanceDiagnostic=str(error))
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
