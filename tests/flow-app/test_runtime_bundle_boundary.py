"""Injected identities/manifests; no signer, Keychain, installed app, or service."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,plistlib,tempfile,unittest
from unittest.mock import patch

R=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('runtime_bundle_owner',R/'scripts/flow-app.py')
package=importlib.util.module_from_spec(spec);spec.loader.exec_module(package)
owner=package.delivery_module()
CURRENT='f'*40

class RuntimeBundleBoundary(unittest.TestCase):
 def test_runtime_identity_matrix(self):
  for fresh,development,identity,accepted in [(False,False,'-',False),(False,True,'-',True),(False,True,'FAKE-CERTIFICATE',False),(True,False,'-',True),(True,False,'FAKE-CERTIFICATE',True)]:
   with self.subTest(fresh=fresh,development=development,identity=identity):
    manifest=dict(source=dict(sourceSHA=CURRENT if fresh else owner.RETAINED_RUNTIME_SOURCE['sourceSHA']))
    if accepted:owner.bundle_runtime_policy(manifest,CURRENT,identity,development=development)
    else:
     with self.assertRaisesRegex(ValueError,'current-source|ad-hoc development'):owner.bundle_runtime_policy(manifest,CURRENT,identity,development=development)

 def fixture(self,root,*,development=False,fresh=False,identity='ad-hoc'):
  app=root/'Lagrangian.app';payload=app/'Contents/Resources/native-reader';runtime=payload/'runtime';runtime.mkdir(parents=True)
  (runtime/'runtime-manifest.json').write_text(json.dumps(dict(source=dict(sourceSHA=CURRENT if fresh else owner.RETAINED_RUNTIME_SOURCE['sourceSHA']))))
  dm=dict(sourceRevision=CURRENT,engineInputSHA256='input',entrypoints=dict(runtime='runtime'))
  dfile=payload/'delivery-manifest.json';dfile.write_text(json.dumps(dm))
  engine=app/'Contents/MacOS/flow-engine';engine.parent.mkdir();engine.write_bytes(b'fake engine, never executed')
  identifier=package.APP_ID+('.development.review-repair2' if development else '')
  (app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=identifier,CFBundleExecutable=package.APP_EXECUTABLE)))
  m=dict(bundleIdentifier=identifier,sourceRevision=CURRENT,sourceDirty=False,version='0.1.0',signing=identity,engineSHA256=hashlib.sha256(engine.read_bytes()).hexdigest(),engineInputSHA256='input',nativeDeliverySHA256=hashlib.sha256(dfile.read_bytes()).hexdigest())
  (app/'Contents/Resources/release.json').write_text(json.dumps(m))
  return app,payload,dm,identifier,engine,m

 def test_retained_production_copy_rejects_before_mutation(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);app,payload,dm,_,_,_=self.fixture(root);before=owner.inventory(payload)
   with patch.object(owner,'verify',return_value=dm),patch.object(owner.shutil,'copytree') as copied,patch.object(owner,'run') as signer:
    with self.assertRaisesRegex(ValueError,'production bundle requires'):owner.copy_signed(payload,root/'candidate','-')
    copied.assert_not_called();signer.assert_not_called()
   self.assertEqual(owner.inventory(payload),before);self.assertFalse((root/'candidate').exists())

 def test_production_build_preflight_precedes_compile_copy(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);_,payload,dm,_,engine,_=self.fixture(root);candidate=root/'candidate/Lagrangian.app'
   with patch.object(package,'delivery_module',return_value=owner),patch.object(owner,'verify',return_value=dm),patch.object(package,'run') as operations,patch.object(package.shutil,'copy2') as copied:
    with self.assertRaisesRegex(ValueError,'production bundle requires'):package.build_bundle(argparse.Namespace(identity='-',bundle_id=package.APP_ID,delivery=payload),candidate,engine,'fake')
    operations.assert_not_called();copied.assert_not_called();self.assertFalse(candidate.exists())

 def test_actual_validator_namespace_and_runtime_decision(self):
  for development,fresh,identity in [(False,False,'ad-hoc'),(True,False,'ad-hoc'),(False,True,'FAKE-CERTIFICATE')]:
   with self.subTest(development=development,fresh=fresh),tempfile.TemporaryDirectory() as tmp:
    app,_,dm,identifier,_,_=self.fixture(Path(tmp),development=development,fresh=fresh,identity=identity)
    with patch.object(package,'delivery_module',return_value=owner),patch.object(owner,'verify',return_value=dm),patch.object(package,'run'),patch.object(package.subprocess,'run',return_value=argparse.Namespace(stderr='Identifier='+identifier+'\n')),patch.object(package,'capture',return_value='Lagrangian 0.1.0') as execute:
     if development or fresh:self.assertEqual(package.validate(app,allow_development=development)['bundleIdentifier'],identifier)
     else:
      with self.assertRaisesRegex(ValueError,'production bundle requires'):package.validate(app)
      execute.assert_not_called()

 def test_production_artifact_uses_same_prepublication_refusal(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);app,_,dm,identifier,engine,m=self.fixture(root)
   sidecar=root/'release.json';m.update(engineBuild=dict(target=package.ENGINE_TARGET,profile=package.ENGINE_PROFILE),engineInputSHA256=hashlib.sha256(engine.read_bytes()).hexdigest());sidecar.write_text(json.dumps(m))
   (app/'Contents/Resources/release.json').write_text(json.dumps(m));dm['engineInputSHA256']=m['engineInputSHA256']
   dfile=app/'Contents/Resources/native-reader/delivery-manifest.json';dfile.write_text(json.dumps(dm));m['nativeDeliverySHA256']=hashlib.sha256(dfile.read_bytes()).hexdigest();(app/'Contents/Resources/release.json').write_text(json.dumps(m))
   with patch.object(package,'delivery_module',return_value=owner),patch.object(owner,'verify',return_value=dm),patch.object(package,'run') as operations,patch.object(package.subprocess,'run',return_value=argparse.Namespace(stderr='Identifier='+identifier+'\n')),patch.object(package,'capture') as execute:
    with self.assertRaisesRegex(ValueError,'production bundle requires'):package.stage_engine_artifact(argparse.Namespace(app=app,manifest=sidecar,engine=engine,output=root/'artifact'))
    execute.assert_not_called();self.assertFalse((root/'artifact').exists())

if __name__=='__main__':unittest.main()
