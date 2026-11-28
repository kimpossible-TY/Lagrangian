"""Bridge fetch/build processes with an engine-local, reauthenticated run context.

This is orchestration only: run selection, inventories, reader checks, signatures
and publication belong to the existing owners. No installed-app/dependency lookup.
"""
from contextlib import contextmanager
import hashlib
from pathlib import Path
import tempfile

import flow_engine_runs
import reader_bundle
import native_delivery_artifact as artifact_transport

CONTEXT = 'native-delivery-context.json'
FIELDS = {'schemaVersion', 'repository', 'runId', 'runHeadSHA', 'enginePath',
          'engineInputSHA256', 'artifactInventorySHA256', 'runRecord', 'deliveryBinding', 'transport'}


def context(package, artifact, destination, repo, record, *, engine_normalized=True):
    owner = package.delivery_module()
    manifest = artifact / package.APP_BUNDLE / 'Contents/Resources/native-reader' / owner.MANIFEST
    transport = artifact_transport.binding(artifact, repository=repo, run_id=record['databaseId'],
        head=record['headSha'], engine_normalized=engine_normalized)
    binding = None
    if manifest.is_file():
        m = owner.read(manifest)
        binding = {key:m.get(key) for key in ('sourceRevision', 'engineInputSHA256', 'helperSHA256',
                   'runtimeManifestSHA256', 'readerBundleChecksum', 'payloadSHA256', 'signing')}
        binding.update(relativeRoot=package.APP_BUNDLE + '/Contents/Resources/native-reader',
                       deliveryManifestSHA256=package.digest(manifest),
                       sourceFilesSHA256=hashlib.sha256(owner.encoded(m.get('sourceFiles'))).hexdigest())
    return dict(schemaVersion=2, repository=repo, runId=str(record['databaseId']),
                runHeadSHA=record['headSha'], enginePath=str(destination / 'flow-engine'),
                engineInputSHA256=package.verify_engine_payload(artifact),
                artifactInventorySHA256=transport['normalizedInventorySHA256'], deliveryBinding=binding, transport=transport,
                runRecord={key:record.get(key) for key in ('databaseId', 'headSha', 'workflowName',
                                                         'headBranch', 'conclusion', 'status', 'url')})


def current_delivery(package, root, engine):
    """Use the full delivery and reader owners, including current helper/source bytes."""
    owner = package.delivery_module()
    m = owner.verify(root)
    for image in m['images']:
        certificate = package.signing_certificate(root / owner.relative(image['path']))
        owner.require((certificate is None if m['signing'] == 'ad-hoc' else
                       certificate is not None and certificate['sha1'] == m['signing']),
                      'Native delivery signing identity mismatch')
    revision = package.capture(['git', '-C', package.ROOT, 'rev-parse', 'HEAD'])
    owner.require(not package.capture(['git', '-C', package.ROOT, 'status', '--porcelain']),
                  'Native delivery requires a clean current checkout')
    owner.require(m['sourceRevision'] == revision and m['sourceFiles'] == owner.source_binding(package.ROOT),
                  'Native delivery sourceRevision/sourceFiles mismatch')
    owner.require(m['integratedSources'] == owner.integrated_sources(package.ROOT), 'Integrated owner mismatch')
    owner.require(m['engineInputSHA256'] == package.digest(engine), 'Native delivery engine input mismatch')
    owner.require(m['helperSHA256'] == package.digest(package.ROOT / 'tools/flow-reader/native/math_layout.mjs'),
                  'Native delivery current helper mismatch')
    owner.require(package.digest(root / 'delivery.py') == package.digest(package.ROOT / 'scripts/stage-native-reader-delivery.py'),
                  'Native delivery source helper mismatch')
    rb = reader_bundle.check_manifest(reader_bundle.load_manifest(root / 'reader-bundle.json'), expected_head_sha=revision)
    reader_bundle.verify_copied_trees(root, rb)
    files = reader_bundle.manifest_files(reader_bundle.collect_entries(package.ROOT, worktree=True))
    owner.require(reader_bundle.bundle_checksum(revision, files) == rb['bundleChecksum'], 'Stale current reader')
    return m


@contextmanager
def consume(package, engine, explicit=None, management_only=False):
    """Yield a verified payload and provenance; retain all inputs on any failure.

    A receipt is only a locator. Re-view its exact R and re-download its artifact
    before trusting it. This also rejects receipt rewriting/replay between runs
    with identical engine bytes. No latest-run query or global last-run state.
    """
    owner = package.delivery_module()
    receipt = engine.parent / CONTEXT
    if management_only:
        owner.require(explicit is None and not receipt.exists(), 'Management-only cannot consume delivery/run context')
        yield None, None
        return
    if not receipt.exists():
        owner.require(explicit is not None, 'Portable delivery missing: use a same-run fetched engine or explicit --delivery')
        root = Path(explicit).expanduser().resolve(strict=True)
        current_delivery(package, root, engine)
        yield root, None
        return
    owner.require(receipt.is_file() and not receipt.is_symlink() and receipt.stat().st_size <= 16384,
                  'Invalid native delivery context path/size')
    c = owner.read(receipt)
    owner.require(isinstance(c, dict) and set(c) == FIELDS and type(c['schemaVersion']) is int
                  and c['schemaVersion'] == 2, 'Unknown native delivery context schema')
    owner.require(c['enginePath'] == str(engine) and engine.name == 'flow-engine', 'Replayed engine context path')
    repo = package.github_repo()
    owner.require(c['repository'] == repo, 'Native delivery context repository mismatch')
    record = flow_engine_runs.select_run(repo, run_id=c['runId'], head_sha=c['runHeadSHA'], runner=package._actions_gh)
    owner.require(str(record['databaseId']) == c['runId'], 'Native delivery context run mismatch')
    owner.require(record['headSha'] == package.capture(['git', '-C', package.ROOT, 'rev-parse', 'HEAD']),
                  'Run head does not match current checkout')
    owner.require(context(package, engine.parent, engine.parent, repo, record) == c, 'Native delivery context/artifact tamper')
    with tempfile.TemporaryDirectory(prefix='native-consumer-') as tmp:
        work = Path(tmp)
        downloaded = work / 'artifact'; downloaded.mkdir()
        package.download_engine_artifact(repo, c['runId'], downloaded)
        artifact = artifact_transport.unpack(downloaded, work / 'payload', repository=repo,
            run_id=c['runId'], head=c['runHeadSHA'])
        owner.require(context(package, artifact, engine.parent, repo, record, engine_normalized=False) == c,
                      'Native delivery context differs from exact run artifact')
        app = artifact / package.APP_BUNDLE
        owner.require((app / 'Contents/Resources/native-reader/delivery-manifest.json').is_file(),
                      'Producer artifact missing current portable native-reader payload')
        release = package.validate(app)
        owner.require(release['sourceRevision'] == c['runHeadSHA'] and not release['sourceDirty']
                      and release['engineInputSHA256'] == c['engineInputSHA256'], 'Stale run application/engine binding')
        sidecar = owner.read(artifact / 'release.json')
        owner.require(sidecar == {**release, 'appExecutableSHA256': package.digest(package.executable(app)),
                                 'bundleChecksum': package.bundle_checksum(app)}, 'Artifact release/sidecar mismatch')
        payload = app / 'Contents/Resources/native-reader'
        m = current_delivery(package, payload, engine)
        # Reuse the original verified artifact files; check the separate reader
        # artifact from R with the existing downloader/archive/manifest owner.
        reader = reader_bundle.fetch_reader_bundle(repo=repo, run_id=c['runId'], head_sha=c['runHeadSHA'],
                                                  dest=work / 'reader', gh=package._actions_gh)
        owner.require(reader_bundle.load_manifest(reader / 'reader-bundle.json') ==
                      reader_bundle.load_manifest(payload / 'reader-bundle.json'), 'Mixed run reader/payload')
        if explicit is not None:
            explicit = Path(explicit).expanduser().resolve(strict=True)
            owner.require(current_delivery(package, explicit, engine) == m, 'Explicit delivery differs from run payload')
        provenance = {**c, 'artifactReleaseSHA256': package.digest(artifact / 'release.json'),
                      'inputDeliveryManifestSHA256': package.digest(payload / owner.MANIFEST),
                      'inputRuntimeManifestSHA256': m['runtimeManifestSHA256'],
                      'readerBundleChecksum': m['readerBundleChecksum'], 'inputSigning': m['signing']}
        yield payload, provenance
        try:
            current = context(package, engine.parent, engine.parent, repo, record)
        except (ValueError, OSError) as error:
            raise ValueError('Native delivery input changed during build: ' + str(error)) from error
        owner.require(current == c,
                      'Native delivery input changed during build')
