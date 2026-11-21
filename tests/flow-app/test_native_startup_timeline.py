"""Value-only production timeline; no AppKit, FIFO, app launch, or real services."""
from pathlib import Path
import hashlib,json,os,subprocess,time,unittest

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=Path('/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/native-cream-review-repair2')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

class StartupTimeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured=os.environ.get('NATIVE_STARTUP_TEST_OUTPUT')
        if not configured:raise unittest.SkipTest('Optional timeline IO tests require explicit fresh task output and one outer Swift lock')
        cls.out=Path(configured).resolve()
        if not cls.out.is_relative_to(OUTPUT) or cls.out.exists() or not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):
            raise RuntimeError('Fresh task output and one outer Swift lock required')
        cls.out.mkdir(parents=True)
        owner=ROOT/'apps/macos/ReadingSessionController.swift'
        source=cls.out/'NativeStartupTimeline.swift'
        declaration=owner.read_text().split('final class NativeStartupTimeline {',1)[1]
        source.write_text('import Foundation\nimport Darwin\nfinal class NativeStartupTimeline {'+declaration)
        harness=ROOT/'tests/flow-app/NativeStartupTimelineTests.swift'
        cls.binary=cls.out/'timeline-tests'
        argv=['/usr/bin/swiftc','-swift-version','5','-warnings-as-errors','-target','arm64-apple-macosx13.0','-module-cache-path',os.environ['SWIFT_MODULECACHE_PATH'],str(source),str(harness),'-o',str(cls.binary)]
        start=time.time();result=subprocess.run(argv,cwd=ROOT,capture_output=True,text=True,timeout=60)
        (cls.out/'compile.json').write_text(json.dumps(dict(argv=argv,cwd=str(ROOT),start=start,end=time.time(),exit=result.returncode,skip=0,inputSHA256={str(owner):sha(owner),str(source):sha(source),str(harness):sha(harness)},adaptation='Exact production timeline declaration plus Foundation/Darwin imports only; no policy or IO implementation changed',stdout=result.stdout,stderr=result.stderr),indent=2)+'\n')
        if result.returncode:raise RuntimeError(result.stderr)

    def scenario(self,name):
        argv=[str(self.binary),name,str(self.out/name)];start=time.time()
        result=subprocess.run(argv,cwd=ROOT,capture_output=True,text=True,timeout=8)
        (self.out/(name+'.json')).write_text(json.dumps(dict(argv=argv,cwd=str(ROOT),start=start,end=time.time(),exit=result.returncode,skip=0,binarySHA256=sha(self.binary),stdout=result.stdout,stderr=result.stderr,AppKit=False,GUI=False),indent=2)+'\n')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_slow_open_does_not_retain_or_block_caller(self):self.scenario('slow-open')
    def test_slow_write_does_not_retain_or_block_caller(self):self.scenario('slow-write')
    def test_failed_open_is_optional(self):self.scenario('failed-open')
    def test_failed_write_is_optional(self):self.scenario('failed-write')
    def test_normal_record_and_private_permissions(self):self.scenario('normal')
    def test_nofollow_and_private_file_guards(self):self.scenario('guards')

if __name__=='__main__':unittest.main()
