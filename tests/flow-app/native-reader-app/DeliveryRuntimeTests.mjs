/** Required portable runtime proof. No package acquisition or GUI. */
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const dev = '/Volumes/devSSD/Developer/lagrangian-native-20261117';
const source = process.env.NATIVE_RUNTIME_STAGE ?? `${dev}/build/delivery-production/runtime`;
const evidence = `${dev}/test-output/delivery-production/NA13`;
const hash = value => createHash('sha256').update(value).digest('hex');
const commands = [];
let root, runtime, node;
const profile = `(version 1)(allow default)(deny network*)(deny file-read* (subpath "${dev}/worktrees") (subpath "${dev}/dependencies") (subpath "/opt/homebrew") (subpath "/Users/taeyoung/.npm") (subpath "/Users/taeyoung/Library/Caches"))`;
function run(args, status = 0, input) {
  const argv = ['/usr/bin/sandbox-exec', '-p', profile, node, ...args];
  const started = Date.now();
  const p = spawnSync(argv[0], argv.slice(1), { input: input && JSON.stringify(input), encoding:'utf8', cwd:root,
    env:{PATH:'/usr/bin:/bin',HOME:root,NODE_PATH:'',NODE_OPTIONS:''}, timeout:120000, maxBuffer:16*1024*1024 });
  commands.push({argv,cwd:root,input,exit:p.status,signal:p.signal,seconds:(Date.now()-started)/1000,stdout:p.stdout,stderr:p.stderr});
  fs.writeFileSync(`${root}/commands.json`, JSON.stringify(commands,null,2));
  assert.equal(p.error,undefined); assert.equal(p.status,status,p.stderr); return p;
}
const verify = status => run([`${runtime}/verify-runtime.mjs`,'--verify',runtime,'--node',node],status);
before(() => {
  assert.ok(fs.existsSync(`${source}/runtime-manifest.json`),'required portable stage missing');
  root=fs.mkdtempSync(`${evidence}/delivery-runtime-`); runtime=`${root}/relocated/runtime`;
  fs.cpSync(source,runtime,{recursive:true,verbatimSymlinks:true}); node=`${runtime}/node/bin/node`;
  assert.match(run(['-e',"require('net').createConnection({host:'127.0.0.1',port:9})"],1).stderr,/EPERM/);
  assert.match(run(['-e',`require('fs').readFileSync('${dev}/dependencies/native-runtime/package.json')`],1).stderr,/EPERM/);
});
after(() => { verify(0); fs.writeFileSync(`${evidence}/delivery-runtime-latest.json`,JSON.stringify({root,commands:commands.length,requiredSkip:0},null,2)); });
test('official release identity, full license and signed bytes survive relocation',()=>{
  const m=JSON.parse(fs.readFileSync(`${runtime}/runtime-manifest.json`));
  const d=JSON.parse(fs.readFileSync(`${runtime}/node-distribution.json`));
  assert.equal(m.node.policy,'portable-bundled'); assert.equal(m.node.version,'v22.23.5');
  assert.equal(m.node.minOS,'11.0'); assert.deepEqual(m.node.hostLibraries,[]);
  assert.equal(m.node.executable,'node/bin/node'); assert.equal(m.node.sha256,hash(fs.readFileSync(node)));
  assert.equal(d.signerFingerprint,'5BE8A3F6C8A5C01D106C0AD820B1A390B168D356');
  assert.equal(d.archive.sha256,'e7131995759b61a0170b646010d2ad35a5d37b4cb0d471f3e8317eac6f742f3d');
  assert.equal(hash(fs.readFileSync(`${runtime}/node/LICENSE`)),d.license.sha256);
  assert.equal(d.macOS13Execution,'unverified'); verify(0);
});
test('final 9b helper computes MathML and base AMS TeX offline with real modules',()=>{
  assert.equal(hash(fs.readFileSync(`${runtime}/helper.mjs`)),'dc100395fc2ea1299c99ec90c201faaed80a1ca5ad0fefaa5d2451278e4a5d76');
  const base={width:320,fontSize:20,font:'MathJaxNewcm',context:{revision:'NA13',generation:1,theme:'light'}};
  const inputs=[{mathML:'<math><mfrac><mi>a</mi><mi>b</mi></mfrac></math>'},
    {kind:'tex',tex:'\\frac{a}{b}',display:true},{kind:'tex',tex:'\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}',display:true}];
  for(const input of inputs){
    const result=JSON.parse(run([`${runtime}/helper.mjs`,'--runtime',runtime],0,{...base,...input}).stdout);
    assert.ok(result.whole.svg.includes('<path')); assert.ok(result.whole.width>0);
    assert.ok(result.runtime.moduleFiles.some(p=>p.includes('/input/mathml')));
    if(input.kind==='tex'){assert.deepEqual(result.runtime.inputPackages,['base','ams']);assert.ok(result.runtime.moduleFiles.some(p=>p.endsWith('/ams/AmsConfiguration.js')));}
  }
});
test('post-sign executable tamper rejects before helper consumption',()=>{
  const bytes=fs.readFileSync(node);
  try {fs.appendFileSync(node,'tamper'); verify(1);} finally {fs.writeFileSync(node,bytes);}
});
test('wrong official distribution and stale helper bindings reject',()=>{
  for(const [file,edit] of [['node-distribution.json',d=>{d.version='v22.0.0';}],['runtime-manifest.json',m=>{m.helperSHA256='0'.repeat(64);}]] ){
    const p=path.join(runtime,file), bytes=fs.readFileSync(p);
    try {const value=JSON.parse(bytes);edit(value);fs.writeFileSync(p,JSON.stringify(value));verify(1);}finally{fs.writeFileSync(p,bytes);}
  }
});
