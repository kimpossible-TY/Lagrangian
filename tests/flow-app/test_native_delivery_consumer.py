"""Required NA14 offline CLI integration; no optional skips or live transport.

Set NA14_ENGINE_ARTIFACT / NA14_READER_ARTIFACT to current-H official producer
outputs, NA14_TEST_ROOT to a fresh DevSSD evidence root. Run once under the shared
Swift lock. gh/download, cache/output locations and service spies are fixtures;
Swift, signing, inventories and require-delivery are actual production operations.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import time
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASE = '09c5186bff1850b17f6e85fe2f3115153520bc94'


def write(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    return path


class NativeDeliveryConsumerCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.environ['NA14_TEST_ROOT']).resolve()
        assert str(cls.root).startswith('/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/artifact-transport-v1/')
        cls.root.mkdir(parents=True, exist_ok=False)
        cls.artifact = Path(os.environ['NA14_ENGINE_ARTIFACT']).resolve(strict=True)
        cls.reader = Path(os.environ['NA14_READER_ARTIFACT']).resolve(strict=True)
        cls.head = subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD'], text=True).strip()
        cls.original_inventory = cls.tree(cls.artifact)
        cls.events = cls.root / 'events.jsonl'
        cls.run_id = '91014'
        cls.cache = cls.root / 'cache'
        cls.build_root = Path(os.environ['NA14_BUILD_ROOT']).resolve()
        assert str(cls.build_root).startswith('/Volumes/devSSD/Developer/lagrangian-native-20261117/build/artifact-transport-v1/')
        cls.app = cls.build_root / cls.root.name / 'Lagrangian.app'
        cls.env = dict(os.environ, FLOW_SIGN_IDENTITY='-', PYTHONDONTWRITEBYTECODE='1', FLOW_DOWNLOAD_CONCURRENCY='1',
                       NA14_FIXTURE_ROOT=str(cls.root), NA14_CURRENT_HEAD=cls.head,
                       NA14_FIXTURE_ENGINE=str(cls.artifact), NA14_FIXTURE_READER=str(cls.reader))
        cli = write(cls.root / 'cli.py', '''import importlib.util,json,os,sys
from pathlib import Path
root=Path(os.environ['NA14_FIXTURE_ROOT'])
script=Path(sys.argv[1]).resolve();sys.argv=sys.argv[1:]
with (root/'events.jsonl').open('a') as f:f.write(json.dumps({'kind':'cli','argv':sys.argv})+'\\n')
sys.path.insert(0,str(script.parent))
if script.name=='flow-app.py':
    spec=importlib.util.spec_from_file_location('fixture_actual_cli',script)
    m=importlib.util.module_from_spec(spec);sys.modules[spec.name]=m;spec.loader.exec_module(m)
    m.DATA=root/'isolated-data';m.LEGACY_DATA=root/'isolated-legacy-data'
    m.engine_cache_dir=lambda run:root/'cache'/str(run)
    original=m.build
    def build(args):
        args.output=Path(os.environ['NA14_BUILD_ROOT'])/root.name/'Lagrangian.app'
        return original(args)
    m.build=build
    if sys.argv[1:2] in (['install'],['rollback'],['migrate']):
        with (root/'events.jsonl').open('a') as f:f.write(json.dumps({'kind':'installer-spy'})+'\\n')
        raise SystemExit('forbidden installer spy')
    m.main()
elif script.name=='fetch-reader-bundle.py':
    import reader_bundle
    reader_bundle.default_staging=lambda head,home=None,platform=None:root/'reader'/head
    raise SystemExit(reader_bundle.main_fetch())
else:raise SystemExit('unknown fixture CLI')
''')
        bins = cls.root / 'bin'; bins.mkdir()
        wrapper = write(bins / 'python3', '#!/bin/sh\nexec ' + str(sys.executable) + ' ' + str(cli) + ' "$@"\n')
        wrapper.chmod(0o755)
        gh = write(bins / 'gh', '#!' + sys.executable + '\n' + '''import json,os,shutil,sys,zipfile
from pathlib import Path
root=Path(os.environ['NA14_FIXTURE_ROOT']);args=sys.argv[1:]
with (root/'events.jsonl').open('a') as f:f.write(json.dumps({'kind':'gh-fixture','argv':args})+'\\n')
if args[:2]==['repo','view']:
    print('fixture/NA14' if '-q' in args else json.dumps({'nameWithOwner':'fixture/NA14'}))
elif args[:2]==['run','view']:
    assert args[2] in ['91014','91015'],args
    print(json.dumps(dict(databaseId=int(args[2]),headSha=os.environ['NA14_CURRENT_HEAD'] if args[2]=='91014' else '1'*40,
        conclusion='success',status='completed',workflowName='Flow engine',headBranch='main',url='https://fixture.invalid/'+args[2])))
elif args[:2]==['run','download']:
    assert args[2] in ['91014','91015'],args
    name=args[args.index('--name')+1];dest=Path(args[args.index('--dir')+1])
    assert name=='flow-engine-darwin-arm64' or name=='reader-bundle-'+os.environ['NA14_CURRENT_HEAD'] or name=='flow-reader-bundle',args
    source=Path(os.environ['NA14_FIXTURE_ENGINE'] if name=='flow-engine-darwin-arm64' else os.environ['NA14_FIXTURE_READER'])
    if (root/'interrupt-download').exists():raise SystemExit(97)
    if name=='flow-engine-darwin-arm64' and (source/'native-delivery-artifact.tar').exists():
        # Explicit offline upload-artifact v4 lossy ZIP model. Only envelope
        # regular files travel through ZIP; modes/links/hidden entries stay in tar.
        zipped=dest.parent/'lossy-v4-fixture.zip'
        with zipfile.ZipFile(zipped,'w',compression=zipfile.ZIP_STORED) as z:
            for file in sorted(source.iterdir()):
                info=zipfile.ZipInfo(file.name);info.external_attr=0o100644<<16
                with file.open('rb') as src,z.open(info,'w') as out:shutil.copyfileobj(src,out)
        dest.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(zipped) as z:z.extractall(dest)
        for file in dest.iterdir():file.chmod(0o644)
    else:shutil.copytree(source,dest,dirs_exist_ok=True,symlinks=True)
else:raise SystemExit('forbidden gh fixture call: '+repr(args))
'''); gh.chmod(0o755)
        spy = write(bins / 'launchctl', '#!/bin/sh\necho service-spy >> "' + str(cls.root / 'forbidden-services') + '"\nexit 98\n'); spy.chmod(0o755)
        cls.env['PATH'] = str(bins) + ':' + os.environ['PATH']
        old = subprocess.check_output(['git', '-C', ROOT, 'show', BASE + ':scripts/mac/auto-update-engine.sh'])
        golden = '\n'.join(line for line in old.decode().splitlines() if line.startswith(('engine=$(python3','reader=$(python3','app=$(python3')))+'\n'
        expected = 'engine=$(python3 scripts/flow-app.py fetch-engine --run-id "$id")\nreader=$(python3 scripts/fetch-reader-bundle.py --run-id "$id")\napp=$(python3 scripts/flow-app.py build --engine "$engine" | tail -1)\n'
        assert golden == expected
        write(cls.root / 'golden-old-sequence.sh', golden)
        write(cls.root / 'golden-binding.json', json.dumps({'source':BASE,'updaterSHA256':hashlib.sha256(old).hexdigest(),
            'sequenceSHA256':hashlib.sha256(golden.encode()).hexdigest(),'transport':'offline fixture','platformTools':'actual','userLiveCalls':0},indent=2))
        code = 'set -euo pipefail\nid=91014\n'+golden+'printf "%s\\n" "$engine" "$reader" "$app"\n'
        result = cls.command('golden-positive', ['bash', '-c', code])
        if result.returncode:
            raise RuntimeError('Required golden CLI failed: '+result.stderr[-3000:])
        cls.receipt = cls.cache / cls.run_id / 'native-delivery-context.json'
        cls.original_receipt = cls.receipt.read_bytes()
        cls.original_receipt_mode = cls.receipt.stat().st_mode & 0o777
        cls.original_app = cls.tree(cls.app)
        cls.engine = cls.cache / cls.run_id / 'flow-engine'

    @staticmethod
    def tree(root):
        return {p.relative_to(root).as_posix():dict(mode=p.lstat().st_mode,
                    sha256=hashlib.sha256(p.read_bytes() if not p.is_symlink() else os.fsencode(os.readlink(p))).hexdigest() if p.is_file() or p.is_symlink() else None)
                for p in root.rglob('*')}

    @classmethod
    def command(cls, name, argv, env=None):
        r = subprocess.run(list(map(str,argv)),cwd=ROOT,env=env or cls.env,text=True,capture_output=True)
        write(cls.root / (name+'.stdout'),r.stdout);write(cls.root / (name+'.stderr'),r.stderr)
        with (cls.root/'commands.jsonl').open('a') as f:f.write(json.dumps({'name':name,'argv':list(map(str,argv)),'exit':r.returncode})+'\n')
        return r

    def tearDown(self):
        self.receipt.write_bytes(self.original_receipt)
        self.receipt.chmod(self.original_receipt_mode)
        self.assertEqual(self.tree(self.app), self.original_app, 'A negative changed the valid app')
        self.assertEqual(self.tree(self.artifact), self.original_inventory, 'Original artifact changed')
        self.assertFalse((self.root/'forbidden-services').exists())
        events = [json.loads(s) for s in self.events.read_text().splitlines()]
        self.assertFalse(any(e['kind']=='installer-spy' for e in events))
        self.assertFalse(any(e['kind']=='gh-fixture' and e['argv'][:2]==['run','list'] for e in events))

    def build_failure(self, name, env=None):
        r=self.command(name,['python3','scripts/flow-app.py','build','--engine',self.engine],env)
        self.assertNotEqual(r.returncode,0,r.stdout)
        self.assertNotIn(str(self.app),r.stdout.splitlines()[-1:] )
        return r

    def test_actual_current_swift_app_and_require_delivery(self):
        release=json.loads((self.app/'Contents/Resources/release.json').read_text())
        payload=json.loads((self.app/'Contents/Resources/native-reader/delivery-manifest.json').read_text())
        runtime=json.loads((self.app/'Contents/Resources/native-reader/runtime/runtime-manifest.json').read_text())
        self.assertEqual(release['sourceRevision'],self.head)
        self.assertEqual(payload['sourceRevision'],self.head)
        self.assertEqual(runtime['source']['sourceSHA'],self.head)
        self.assertFalse(release['sourceDirty'])
        self.assertGreater(release['appBuild']['compileElapsedSeconds'],0)
        self.assertIn('/usr/bin/swiftc',release['appBuild']['compilerArgv'])
        self.assertEqual(release['nativeDeliveryInput']['runId'],self.run_id)
        self.assertNotEqual(release['engineInputProvenance']['binaryReportedCommit'],self.head)
        self.assertEqual(release['engineInputProvenance']['retained']['engineBuild']['target'],'aarch64-apple-darwin')
        r=self.command('require-delivery',[sys.executable,'-B','scripts/verify-native-reader-app.py',self.app,'--require-delivery','--source-revision',self.head,'--output',self.root/'integrity.json'])
        self.assertEqual(r.returncode,0,r.stderr)

    def test_receipt_schema_wrong_head_mixed_run_replay(self):
        original=json.loads(self.original_receipt)
        for name, changes in [('schema',{'schemaVersion':3}),('wrong-head',{'runHeadSHA':'0'*40}),
                              ('mixed-run',{'runId':'91015'}),('replay-path',{'enginePath':str(self.cache/'replayed'/'flow-engine')}),
                              ('path-escape',{'enginePath':str(self.engine.parent/'../flow-engine')})]:
            with self.subTest(name=name):
                self.receipt.write_text(json.dumps({**original,**changes}))
                self.build_failure(name)
        # Even a rewritten locator with otherwise identical R/H/engine/artifact
        # must name the successful run actually selected; no global latest query.
        self.receipt.write_bytes(self.original_receipt)

    def test_missing_context_requires_explicit_delivery(self):
        self.receipt.unlink()
        self.build_failure('missing-context')

    def test_tamper_missing_dependency_oldapp_stale_helper_afterhash(self):
        paths={'tamper':self.engine,'missing-dependency':self.cache/self.run_id/'Lagrangian.app/Contents/Resources/native-reader/runtime/helper.mjs',
               'cached-old-app':self.cache/self.run_id/'Lagrangian.app/Contents/Resources/release.json',
               'source-helper-stale':self.cache/self.run_id/'Lagrangian.app/Contents/Resources/native-reader/delivery.py',
               'post-hash-drift':self.cache/self.run_id/'Lagrangian.app/Contents/Resources/native-reader/runtime/runtime-manifest.json'}
        for name,path in paths.items():
            with self.subTest(name=name):
                original=path.read_bytes()
                try:
                    if name=='missing-dependency':path.unlink()
                    else:path.write_bytes(original+b'\nNA14 tamper')
                    self.build_failure(name)
                finally:path.write_bytes(original)

    def test_no_implicit_adhoc_or_invalid_identity(self):
        env=dict(self.env);env.pop('FLOW_SIGN_IDENTITY')
        self.build_failure('missing-signing-identity',env)
        env['FLOW_SIGN_IDENTITY']='NA14 nonexistent identity'
        self.build_failure('wrong-signing-identity',env)

    def test_interrupted_transport_preserves_valid_cache_and_app(self):
        marker=write(self.root/'interrupt-download','fixture transport interruption\n')
        before=self.tree(self.cache/self.run_id)
        try:
            self.build_failure('interrupt-build')
            r=self.command('interrupt-refetch',['python3','scripts/flow-app.py','fetch-engine','--run-id',self.run_id])
            self.assertNotEqual(r.returncode,0)
            self.assertEqual(self.tree(self.cache/self.run_id),before)
        finally:marker.unlink()

    def test_tampered_engine_is_not_probed_before_authentication(self):
        original=self.engine.read_bytes();marker=self.root/'untrusted-engine-executed'
        try:
            self.engine.write_text('#!/bin/sh\necho unsafe > "'+str(marker)+'"\nprintf "fixture --follow-system-theme\\n"\n')
            self.build_failure('untrusted-engine-no-probe')
            self.assertFalse(marker.exists(),'Unverified cache engine was executed')
        finally:self.engine.write_bytes(original)

    def test_fetch_rejects_escaping_engine_before_chmod_or_probe(self):
        negative=self.root/'escaping-producer';negative.mkdir()
        marker=negative/'untrusted-executed';outside=negative/'outside-engine'
        outside.write_text('#!/bin/sh\necho unsafe > "'+str(marker)+'"\nprintf "fixture --follow-system-theme\\n"\n')
        outside.chmod(0o700);mode=outside.stat().st_mode
        artifact=negative/'artifact';artifact.mkdir()
        (artifact/'flow-engine').symlink_to(outside)
        checksum=hashlib.sha256(outside.read_bytes()).hexdigest()
        write(artifact/'flow-engine.sha256',checksum+'  flow-engine\n')
        release=json.loads((self.cache/self.run_id/'release.json').read_text());release['engineInputSHA256']=checksum
        write(artifact/'release.json',json.dumps(release))
        env=dict(self.env,NA14_FIXTURE_ROOT=str(negative),NA14_FIXTURE_ENGINE=str(artifact))
        r=self.command('escape-before-chmod',['python3','scripts/flow-app.py','fetch-engine','--run-id',self.run_id],env)
        self.assertNotEqual(r.returncode,0)
        self.assertEqual(outside.stat().st_mode,mode)
        self.assertFalse(marker.exists())
        self.assertFalse((negative/'cache'/self.run_id).exists())

    def test_successful_refetch_is_atomic_and_bounded(self):
        original=self.tree(self.cache/self.run_id)
        r=self.command('successful-refetch',['python3','scripts/flow-app.py','fetch-engine','--run-id',self.run_id])
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(r.stdout.strip(),str(self.engine))
        self.assertEqual(self.tree(self.cache/self.run_id),original)
        self.assertFalse(list(self.cache.glob('.incoming-*')))
        c=json.loads(self.receipt.read_text())
        self.assertEqual(c['deliveryBinding']['sourceRevision'],self.head)
        self.assertEqual(c['deliveryBinding']['signing'],'ad-hoc')
        self.assertEqual(c['runRecord']['databaseId'],int(self.run_id))

    def test_producer_without_portable_payload_fails_before_install(self):
        negative=self.root/'missing-producer';negative.mkdir()
        artifact=negative/'artifact';artifact.mkdir()
        for name in ['flow-engine','flow-engine.sha256','release.json']:
            shutil.copy2(self.cache/self.run_id/name,artifact/name)
        shutil.copytree(self.app,self.build_root/negative.name/'Lagrangian.app',symlinks=True)
        env=dict(self.env,NA14_FIXTURE_ROOT=str(negative),NA14_FIXTURE_ENGINE=str(artifact))
        fetched=self.command('missing-producer-fetch',['python3','scripts/flow-app.py','fetch-engine','--run-id',self.run_id],env)
        self.assertNotEqual(fetched.returncode,0)
        self.assertIn('archive missing',fetched.stderr)
        self.assertEqual(self.tree(self.build_root/negative.name/'Lagrangian.app'),self.original_app)

    def test_actual_interrupt_preserves_stage(self):
        before=self.tree(self.cache/self.run_id)
        argv=['python3','scripts/flow-app.py','build','--engine',str(self.engine)]
        with (self.root/'signal-interrupt.stdout').open('w') as out, (self.root/'signal-interrupt.stderr').open('w') as err:
            child=subprocess.Popen(argv,cwd=ROOT,env=self.env,stdout=out,stderr=err,start_new_session=True)
            try:
                deadline=time.monotonic()+20
                while not list(self.app.parent.glob('.flow-build-*')) and child.poll() is None and time.monotonic()<deadline:
                    time.sleep(0.02)
                self.assertIsNone(child.poll(),'Build ended before interruption')
                self.assertTrue(list(self.app.parent.glob('.flow-build-*')))
                os.killpg(child.pid,signal.SIGTERM)
                code=child.wait(timeout=15)
                self.assertNotEqual(code,0)
                with (self.root/'commands.jsonl').open('a') as f:f.write(json.dumps({'name':'signal-interrupt','argv':argv,'exit':code})+'\n')
            finally:
                if child.poll() is None:os.killpg(child.pid,signal.SIGKILL);child.wait()
                for path in self.app.parent.glob('.flow-build-*'):shutil.rmtree(path)
        self.assertEqual(self.tree(self.cache/self.run_id),before)

    def test_actual_after_hash_input_drift_preserves_app(self):
        target=self.cache/self.run_id/'Lagrangian.app/Contents/Resources/native-reader/runtime/helper.mjs'
        original=target.read_bytes()
        argv=['python3','scripts/flow-app.py','build','--engine',str(self.engine)]
        with (self.root/'during-build-drift.stdout').open('w') as out, (self.root/'during-build-drift.stderr').open('w') as err:
            child=subprocess.Popen(argv,cwd=ROOT,env=self.env,stdout=out,stderr=err,start_new_session=True)
            try:
                deadline=time.monotonic()+180
                while not list(self.app.parent.glob('.flow-build-*/Lagrangian.app/Contents/MacOS/flow-engine')) and child.poll() is None and time.monotonic()<deadline:
                    time.sleep(0.05)
                self.assertIsNone(child.poll(),'Build ended before Swift candidate')
                self.assertTrue(list(self.app.parent.glob('.flow-build-*/Lagrangian.app/Contents/MacOS/flow-engine')))
                target.write_bytes(original+b'\n// NA14 concurrent input drift\n')
                code=child.wait(timeout=180)
                self.assertNotEqual(code,0)
                with (self.root/'commands.jsonl').open('a') as f:f.write(json.dumps({'name':'during-build-drift','argv':argv,'exit':code})+'\n')
            finally:
                target.write_bytes(original)
                if child.poll() is None:os.killpg(child.pid,signal.SIGKILL);child.wait()
        self.assertIn('input changed during build',(self.root/'during-build-drift.stderr').read_text())

    def test_raw_archive_drift_and_digest_receipt_replay_fail_closed(self):
        original=json.loads(self.original_receipt)
        original['transport']['archiveSHA256']='0'*64
        self.receipt.write_text(json.dumps(original))
        self.build_failure('raw-digest-replay')
        self.receipt.write_bytes(self.original_receipt)
        archive=self.cache/self.run_id/'.native-transport/native-delivery-artifact.tar'
        with archive.open('r+b') as stream:
            first=stream.read(1);stream.seek(0);stream.write(bytes([first[0]^1]))
        try:self.build_failure('cached-raw-archive-tamper')
        finally:
            with archive.open('r+b') as stream:stream.write(first)

    def test_z_producer_does_not_repair_flat_signed_payload_modes(self):
        bad=self.build_root/'broken-flat/Lagrangian.app';shutil.copytree(self.app,bad,symlinks=True)
        path=bad/'Contents/Resources/native-reader/runtime/node/bin/node';path.chmod(0o644)
        output=self.build_root/'existing-valid-transport';shutil.copytree(self.artifact,output)
        before=self.tree(output)
        r=self.command('producer-flat-mode-reject',[sys.executable,'-B','scripts/flow-app.py','stage-engine-artifact',
            '--app',bad,'--engine',self.engine,'--manifest',self.app.parent/'release.json','--output',output,
            '--repository','fixture/NA14','--run-id',self.run_id])
        self.assertNotEqual(r.returncode,0)
        self.assertEqual(self.tree(output),before)
        self.assertEqual(path.stat().st_mode&0o777,0o644)

    def test_contextless_engine_cannot_silently_downgrade(self):
        standalone=self.root/'contextless';standalone.mkdir()
        shutil.copy2(self.engine,standalone/'flow-engine')
        r=self.command('standalone-missing-delivery',['python3','scripts/flow-app.py','build','--engine',standalone/'flow-engine'])
        self.assertNotEqual(r.returncode,0)


if __name__=='__main__':unittest.main()
