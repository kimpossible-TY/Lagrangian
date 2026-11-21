/** Required installed-runtime and producer faults. No npm/network acquisition. */
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { sha, inventory, packages, fontPreservation } from '../../../scripts/prepare-native-reader-runtime.mjs';

const dev = '/Volumes/devSSD/Developer/lagrangian-native-20261117';
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const stage = process.env.NATIVE_RUNTIME_STAGE ?? `${dev}/build/delivery-production/runtime`;
const evidence = `${dev}/test-output/delivery-production/NA13/runtime`;
const materialized = `${dev}/dependencies/native-runtime`;
const sourceNode = `${dev}/dependencies/portable-node/node-v22.23.5-darwin-arm64/bin/node`;
let node;
const producer = `${repo}/scripts/prepare-native-reader-runtime.mjs`;
const commands = [];
let root, installed, originalManifest;
const env = { PATH: '/usr/bin:/bin', HOME: `${dev}/tmp/delivery-production/empty-home`, NODE_PATH: '/nonexistent/poison', NODE_OPTIONS: '', TMPDIR: `${dev}/tmp/delivery-production` };
function run(argv, expected = 0, timeout = 60000, input) {
  const started = Date.now();
  const p = spawnSync(argv[0], argv.slice(1), { encoding: 'utf8', env, cwd: root, timeout, killSignal: 'SIGKILL', maxBuffer: 16 * 1024 * 1024, input });
  commands.push({ argv, input, exit: p.status, signal: p.signal, error: p.error?.code, elapsedMS: Date.now() - started, stdout: p.stdout, stderr: p.stderr });
  fs.writeFileSync(`${root}/commands.json`, JSON.stringify(commands, null, 2) + '\n');
  assert.equal(p.error, undefined, p.error?.message);
  assert.equal(p.status, expected, p.stderr);
  return p;
}
const profile = `(version 1)(allow default)(deny network*)(deny file-read* (subpath "${dev}/worktrees") (subpath "${dev}/dependencies") (subpath "/Users/taeyoung/.npm") (subpath "/Users/taeyoung/Library/Caches") (subpath "/Users/taeyoung/.node_modules") (subpath "/Users/taeyoung/.node_libraries") (subpath "/opt/homebrew/lib/node_modules") (subpath "/opt/homebrew/Cellar/node/26.13.1/lib/node"))`;
const offline = args => ['/usr/bin/sandbox-exec', '-p', profile, node, ...args];
const verify = (expected = 0, exe = node) => run(offline([`${installed}/verify-runtime.mjs`, '--verify', installed, '--node', exe]), expected, 120000);
function withFile(rel, edit, action) {
  const p = `${installed}/${rel}`, bytes = fs.readFileSync(p);
  try { edit(p, Buffer.from(bytes)); action(); } finally { fs.writeFileSync(p, bytes); }
}
const prepareArgs = (source = materialized, helper = `${stage}/helper.mjs`, proof = `${stage}/proof-input.json`, output = `${root}/atomic-runtime`) =>
  [node, producer, '--runtime-source', source, '--helper', helper, '--proof-input', proof, '--node', sourceNode, '--output', output];

before(() => {
  assert.ok(fs.existsSync(`${stage}/runtime-manifest.json`), 'required prepared runtime missing; run test_runtime.py first');
  fs.mkdirSync(evidence, { recursive: true });
  root = fs.mkdtempSync(`${evidence}/node-run-`);
  installed = `${root}/installed/Contents/Resources/runtime`;
  fs.cpSync(stage, installed, { recursive: true, verbatimSymlinks: true });
  node = `${installed}/node/bin/node`;
  originalManifest = sha(fs.readFileSync(`${installed}/runtime-manifest.json`));
  // An OS probe must actually fail before any offline success is counted.
  const p = run(offline(['-e', "require('net').createConnection({host:'127.0.0.1',port:9})"]), 1);
  assert.match(p.stderr, /EPERM/);
});
after(() => {
  assert.equal(sha(fs.readFileSync(`${installed}/runtime-manifest.json`)), originalManifest);
  verify(); // fault restoration must preserve the entire accepted payload
  fs.writeFileSync(`${evidence}/latest-node.json`, JSON.stringify({ output: root, commandCount: commands.length, requiredSkip: 0 }, null, 2) + '\n');
});

test('relocated verifier needs no checkout, scratch, cache or network', () => {
  const report = JSON.parse(verify().stdout);
  assert.equal(report.packages, 18);
  assert.ok(report.fileCount > 5000);
});
test('every locked archive and all dynamic modules/font bytes are present', () => {
  const locked = packages(installed);
  assert.equal(locked.length, 18);
  const entries = inventory(installed);
  assert.equal(entries.filter(p => /\/woff2\/.*\.woff2$/.test(p.path)).length, 105);
  assert.ok(entries.filter(p => /\/cjs\/svg\/dynamic\/[^/]+\.js$/.test(p.path)).length > 30);
  for (const module of ['input/mathml.js', 'input/tex.js', 'adaptors/liteAdaptor.js', 'output/svg.js'])
    assert.ok(entries.some(p => p.path.endsWith('/cjs/' + module)), module);
});
test('missing module is rejected with no global fallback', () => {
  const p = 'node_modules/@mathjax/src/cjs/mathjax.js';
  withFile(p, file => fs.unlinkSync(file), () => {
    verify(1);
    const input = JSON.stringify({ mathML: '<math><mfrac><mi>a</mi><mi>b</mi></mfrac></math>', width: 320, fontSize: 20, font: 'MathJaxNewcm', context: { revision: 'NA11', generation: 1, theme: 'light' } });
    const result = run(offline([`${installed}/helper.mjs`, '--runtime', installed]), 2, 60000, input);
    assert.match(result.stderr, /math-runtime-failure/);
  });
});
test('missing nondefault font range and WOFF2 are rejected', () => {
  for (const p of ['node_modules/@mathjax/mathjax-newcm-font/cjs/svg/dynamic/hebrew.js', 'node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ml.woff2'])
    withFile(p, file => fs.unlinkSync(file), () => verify(1));
});
test('file and lock tamper fail before consumption', () => {
  for (const p of ['node_modules/@mathjax/src/cjs/mathjax.js', 'package-lock.json', 'helper.mjs'])
    withFile(p, (file, bytes) => fs.writeFileSync(file, Buffer.concat([bytes, Buffer.from(' ')])), () => verify(1));
});
test('original font notices and official GUST/LPPL text are mandatory', () => {
  const preserved = fontPreservation(installed);
  assert.deepEqual(preserved.classes, { 'original-gust': 84, 'mathjax-plus-original-gust': 21 });
  assert.equal(preserved.fontCount, 105);
  withFile('THIRD-PARTY-NOTICES.md', (p, bytes) => fs.writeFileSync(p, bytes.toString().replace('native-font-preservation-v1', 'removed-font-preservation')), () => {
    assert.throws(() => fontPreservation(installed), /font-original-notices-missing/); verify(1);
  });
  withFile('THIRD-PARTY-NOTICES.md', (p, bytes) => fs.writeFileSync(p, bytes.toString().replace('% This is version 1.0, dated 22 June 2009, of the GUST Font License.', '% Removed official GUST license text.')), () => {
    assert.throws(() => fontPreservation(installed), /font-official-terms-mismatch/);
  });
});
test('external symlink rejected; internal npm bin links survive relocation', () => {
  const p = `${installed}/external.mjs`;
  fs.symlinkSync('/etc/hosts', p);
  try { verify(1); } finally { fs.unlinkSync(p); }
  assert.ok(inventory(installed).some(p => p.link && p.path.startsWith('node_modules/.bin/')));
});
test('manifest path traversal and helper hash substitution are rejected', () => {
  withFile('runtime-manifest.json', (p, bytes) => {
    const m = JSON.parse(bytes); m.entrypoint = '../helper.mjs'; fs.writeFileSync(p, JSON.stringify(m));
  }, () => verify(1));
  withFile('runtime-manifest.json', (p, bytes) => {
    const m = JSON.parse(bytes); m.helperSHA256 = '0'.repeat(64); fs.writeFileSync(p, JSON.stringify(m));
  }, () => verify(1));
});
test('lock SRI cannot be satisfied by a modified authoritative archive', () => {
  const p = JSON.parse(fs.readFileSync(`${installed}/acquisition.json`))[0].file;
  withFile(p, (file, bytes) => { bytes[bytes.length - 2] ^= 1; fs.writeFileSync(file, bytes); }, () => assert.throws(() => packages(installed), /archive-SRI/));
});
test('missing and incompatible Node preflight return bounded nonzero', () => {
  verify(1, '/nonexistent/node');
  const fake = `${root}/incompatible-node`;
  fs.writeFileSync(fake, '#!/bin/sh\necho \'{"version":"v18.0.0","arch":"arm64","platform":"darwin"}\'\n', { mode: 0o755 });
  const result = verify(1, fake);
  assert.match(result.stderr, /node-incompatible/);
});
test('child command timeout kills an unresponsive Node preflight', () => {
  const fake = `${root}/unresponsive-node`;
  fs.writeFileSync(fake, '#!/bin/sh\nexec /bin/sleep 30\n', { mode: 0o755 });
  const start = Date.now();
  const result = verify(1, fake);
  assert.match(result.stderr, /ETIMEDOUT/);
  assert.ok(Date.now() - start < 20000);
});
test('partial source, external link and helper mismatch preserve valid stage', () => {
  const output = `${root}/atomic-runtime`;
  fs.cpSync(stage, output, { recursive: true, verbatimSymlinks: true });
  const before = sha(fs.readFileSync(`${output}/runtime-manifest.json`));
  const partial = `${root}/partial`; fs.mkdirSync(partial);
  for (const name of ['package.json', 'package-lock.json', 'THIRD-PARTY-NOTICES.md', 'acquisition.json']) fs.copyFileSync(`${materialized}/${name}`, `${partial}/${name}`);
  run(prepareArgs(partial), 1);
  assert.equal(sha(fs.readFileSync(`${output}/runtime-manifest.json`)), before);
  fs.symlinkSync('/etc/hosts', `${partial}/outside`);
  assert.match(run(prepareArgs(partial), 1).stderr, /external-symlink/);
  const wrong = `${root}/wrong-proof.json`;
  fs.writeFileSync(wrong, JSON.stringify({ helperSHA256: '0'.repeat(64) }));
  assert.match(run(prepareArgs(materialized, `${stage}/helper.mjs`, wrong), 1, 120000).stderr, /proof-helper-mismatch/);
  assert.equal(sha(fs.readFileSync(`${output}/runtime-manifest.json`)), before);
});
test('a dangling output symlink is rejected and preserved', () => {
  const output = `${root}/dangling-output`;
  fs.symlinkSync(`${root}/absent-external-stage`, output);
  const result = run(prepareArgs(materialized, `${stage}/helper.mjs`, `${stage}/proof-input.json`, output), 1, 120000);
  assert.match(result.stderr, /output-type/);
  assert.ok(fs.lstatSync(output).isSymbolicLink());
});
test('atomic replacement verifies a complete candidate; arbitrary helper stays hash-bound', () => {
  const output = `${root}/atomic-runtime`, helper = `${root}/future-helper.mjs`;
  fs.writeFileSync(helper, 'process.stderr.write("future helper fixture only"); process.exitCode=2;\n');
  const args = [node, producer, '--runtime-source', materialized, '--helper', helper, '--node', sourceNode, '--output', output];
  run(args, 0, 180000); // original four-option contract, no supplemental proof
  assert.equal(sha(fs.readFileSync(`${output}/helper.mjs`)), sha(fs.readFileSync(helper)));
  assert.ok(!fs.existsSync(output + '.lock'));
  // Concurrent/stale guard fails without touching the accepted stage.
  fs.mkdirSync(output + '.lock');
  const before = sha(fs.readFileSync(`${output}/runtime-manifest.json`));
  try { run(args, 1, 120000); }
  finally { fs.rmdirSync(output + '.lock'); }
  assert.equal(sha(fs.readFileSync(`${output}/runtime-manifest.json`)), before);
});
test('killing a producer during copy preserves accepted bytes and leaves a detectable stale guard', async () => {
  const output = `${root}/atomic-runtime`, before = sha(fs.readFileSync(`${output}/runtime-manifest.json`));
  const argv = prepareArgs(), started = Date.now();
  const child = spawn(argv[0], argv.slice(1), { env, cwd: root, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '', stderr = '', killed = false;
  child.stdout.on('data', b => { stdout += b; }); child.stderr.on('data', b => { stderr += b; });
  const status = await new Promise((resolve, reject) => {
    const deadline = setTimeout(() => { child.kill('SIGKILL'); reject(new Error('required partial-copy condition never observed')); }, 30000);
    const poll = setInterval(() => {
      const partial = fs.readdirSync(root).filter(n => n.startsWith('.runtime-'));
      if (partial.some(n => fs.existsSync(`${root}/${n}/node_modules`) && !fs.existsSync(`${root}/${n}/helper.mjs`))) {
        killed = true; child.kill('SIGKILL'); clearInterval(poll);
      }
    }, 5);
    child.once('error', reject);
    child.once('exit', (exit, signal) => { clearTimeout(deadline); clearInterval(poll); resolve({ exit, signal }); });
  });
  commands.push({ argv, ...status, stdout, stderr, elapsedMS: Date.now() - started });
  fs.writeFileSync(`${root}/commands.json`, JSON.stringify(commands, null, 2) + '\n');
  assert.ok(killed, 'must actually interrupt partial copy'); assert.equal(status.signal, 'SIGKILL');
  assert.equal(sha(fs.readFileSync(`${output}/runtime-manifest.json`)), before);
  assert.ok(fs.existsSync(output + '.lock'));
  // The process is reaped; only now can the test remove its stale guard/candidate.
  fs.rmdirSync(output + '.lock');
  for (const name of fs.readdirSync(root).filter(n => n.startsWith('.runtime-'))) fs.rmSync(`${root}/${name}`, { recursive: true });
});
