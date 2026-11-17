/** Local preparation is separate from consumption: this CLI never runs npm or fetch.
 * All package files must match SRI-authenticated registry archives. macOS only.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import { spawnSync } from 'node:child_process';

export const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const json = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const encode = value => JSON.stringify(value, null, 2) + '\n';
const write = (p, v) => fs.writeFileSync(p, encode(v));
const must = (ok, code) => { if (!ok) throw new Error(code); };
const safe = p => typeof p === 'string' && p.length > 0 && !p.includes('\\') && !path.isAbsolute(p) && p.split('/').every(c => c && c !== '.' && c !== '..');
export function command(exe, args, options = {}) {
  const p = spawnSync(exe, args, { encoding: 'utf8', timeout: 15000, killSignal: 'SIGKILL', maxBuffer: 16 * 1024 * 1024,
    env: { PATH: '/usr/bin:/bin', HOME: '/nonexistent', NODE_PATH: '', NODE_OPTIONS: '' }, ...options });
  must(!p.error && p.status === 0, `command-failed:${exe}:${p.error?.code ?? p.status}:${(p.stderr ?? '').slice(0, 300)}`);
  return p.stdout;
}
export function inventory(root) {
  const records = [];
  function visit(dir) {
    for (const name of fs.readdirSync(path.join(root, dir)).sort()) {
      const rel = dir ? `${dir}/${name}` : name;
      must(safe(rel), 'unsafe-path');
      const p = path.join(root, rel), st = fs.lstatSync(p);
      if (st.isDirectory()) visit(rel);
      else if (st.isSymbolicLink()) {
        const target = fs.readlinkSync(p), real = fs.realpathSync(p);
        must(!path.isAbsolute(target) && real.startsWith(root + path.sep) && fs.statSync(real).isFile(), 'external-symlink');
        records.push({ path: rel, link: target, sha256: sha(target) });
      } else {
        must(st.isFile(), 'non-regular-file');
        records.push({ path: rel, bytes: st.size, sha256: sha(fs.readFileSync(p)) });
      }
    }
  }
  visit('');
  return records;
}
// npm's registry tar format. Reject links, special entries, duplicate paths and
// traversal before touching disk. Never use tar extraction on untrusted names.
function archiveFiles(bytes) {
  const data = gunzipSync(bytes, { maxOutputLength: 512 * 1024 * 1024 });
  const files = new Map();
  const str = (h, a, b) => h.subarray(a, b).toString().replace(/\0.*$/s, '');
  for (let pos = 0; pos + 512 <= data.length;) {
    const h = data.subarray(pos, pos + 512); pos += 512;
    if (h.every(v => v === 0)) break;
    const size = Number.parseInt(str(h, 124, 136).trim(), 8);
    must(Number.isSafeInteger(size) && size >= 0 && pos + size <= data.length, 'archive-size');
    const name = str(h, 0, 100), prefix = str(h, 345, 500);
    const full = prefix ? prefix + '/' + name : name, type = str(h, 156, 157);
    must(full.startsWith('package/') && safe(full.replace(/\/$/, '')), 'archive-path');
    if (type !== '5') {
      must(type === '0' || type === '', `archive-type:${type}`);
      const rel = full.slice(8);
      must(safe(rel) && !files.has(rel), 'archive-duplicate');
      files.set(rel, { bytes: size, sha256: sha(data.subarray(pos, pos + size)) });
    }
    pos += Math.ceil(size / 512) * 512;
  }
  must(files.size > 0, 'empty-archive');
  return files;
}
export function packages(root) {
  const pkg = json(path.join(root, 'package.json')), lock = json(path.join(root, 'package-lock.json'));
  must(pkg.private === true && lock.lockfileVersion === 3, 'package-contract');
  for (const name of ['@mathjax/src', '@mathjax/mathjax-newcm-font'])
    must(pkg.dependencies[name] === '4.1.3' && lock.packages['node_modules/' + name]?.version === '4.1.3', 'exact-pins');
  must(encode(pkg.dependencies) === encode(lock.packages[''].dependencies), 'lock-root-mismatch');
  const acquisition = json(path.join(root, 'acquisition.json'));
  const result = [];
  const allowed = new Set(['node_modules/.package-lock.json']);
  const bins = new Map();
  for (const [rel, entry] of Object.entries(lock.packages)) {
    if (!rel) continue;
    must(safe(rel) && rel.startsWith('node_modules/') && /^https:\/\/registry\.npmjs\.org\//.test(entry.resolved) && /^sha512-/.test(entry.integrity), 'lock-package');
    const record = acquisition.find(a => a.package === rel);
    must(record && safe(record.file) && record.file.startsWith('archives/') && record.url === entry.resolved, 'missing-archive');
    const bytes = fs.readFileSync(path.join(root, record.file));
    must('sha512-' + createHash('sha512').update(bytes).digest('base64') === entry.integrity, 'archive-SRI');
    const contents = archiveFiles(bytes), manifest = json(path.join(root, rel, 'package.json'));
    must(manifest.version === entry.version && manifest.license === entry.license, 'package-version-license');
    for (const [name, expected] of contents) {
      const p = path.join(root, rel, name), st = fs.lstatSync(p);
      must(st.isFile() && st.size === expected.bytes && sha(fs.readFileSync(p)) === expected.sha256, `archive-file-mismatch:${rel}/${name}`);
      allowed.add(`${rel}/${name}`);
    }
    for (const [name, target] of Object.entries(entry.bin ?? {})) {
      must(safe(name) && !name.includes('/') && safe(target) && contents.has(target), 'package-bin');
      bins.set(`node_modules/.bin/${name}`, path.join(root, rel, target));
    }
    const licenses = [...contents.keys()].filter(n => /(^|\/)(LICENSE[^/]*|NOTICE[^/]*|COPYING[^/]*)$/i.test(n));
    // The font npm archive omits LICENSE. Same-version embedded WOFF2 notices
    // and the publisher's declaration are preserved in the committed supplement.
    must(licenses.length > 0 || rel === 'node_modules/@mathjax/mathjax-newcm-font', 'license-missing');
    result.push({ path: rel, ...entry, archiveSHA256: sha(bytes), fileCount: contents.size, licenses });
  }
  for (const f of inventory(path.join(root, 'node_modules'))) {
    const rel = 'node_modules/' + f.path;
    must(allowed.has(rel) || (f.link && bins.has(rel) && fs.realpathSync(path.join(root, rel)) === bins.get(rel)), `unlocked-file:${rel}`);
  }
  must(result.length === acquisition.length, 'acquisition-count');
  const notices = fs.readFileSync(path.join(root, 'THIRD-PARTY-NOTICES.md'), 'utf8');
  must(notices.includes('Font upstream evidence') && notices.includes('GUST Font License') && notices.includes('LPPL Version 1.3c') && notices.includes('Copyright'), 'font-notice-missing');
  return result;
}
export function fontPreservation(root) {
  const notice = fs.readFileSync(path.join(root, 'THIRD-PARTY-NOTICES.md'), 'utf8');
  const block = /<!-- native-font-preservation-v1\n([^]*?)\n-->/.exec(notice);
  must(block, 'font-original-notices-missing');
  const evidence = JSON.parse(block[1]), fonts = [];
  const classes = { 'original-gust': 0, 'mathjax-plus-original-gust': 0 };
  for (const f of evidence.fonts) {
    must(safe(f.path) && /^node_modules\/@mathjax\/mathjax-newcm-font\/chtml\/woff2\/[^/]+\.woff2$/.test(f.path), 'font-notice-path');
    must(sha(fs.readFileSync(path.join(root, f.path))) === f.sha256, 'font-original-bytes-mismatch');
    const copyrights = [...new Set(f.names.filter(n => n.nameID === 0 && n.value.trim()).map(n => n.value))];
    must(copyrights.length === 1 && sha(copyrights[0]) === f.noticeSHA256 && copyrights[0].includes('(C) 2019-2021 Antonis Tsolomitis.') && copyrights[0].includes('GUST Font License'), 'font-original-notice-mismatch');
    const category = copyrights[0].startsWith('Copyright (c) 2024 MathJax, Inc.') ? 'mathjax-plus-original-gust' : 'original-gust';
    must(f.category === category, 'font-notice-category');
    classes[category]++;
    fonts.push({ path: f.path, sha256: f.sha256, noticeSHA256: f.noticeSHA256, category });
  }
  const actual = fs.readdirSync(path.join(root, 'node_modules/@mathjax/mathjax-newcm-font/chtml/woff2')).filter(n => n.endsWith('.woff2'));
  must(evidence.count === 105 && fonts.length === 105 && new Set(fonts.map(f => f.path)).size === 105 && actual.length === 105 && classes['original-gust'] === 84 && classes['mathjax-plus-original-gust'] === 21, 'font-notice-count');
  const terms = [
    ['GUST-FONT-LICENSE.txt', 'https://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt', '49ea6cb9257bbee0a3979c48a774cd221550ac1c20c95549efe45fc99cc18050'],
    ['LPPL-1.3c.txt', 'https://www.latex-project.org/lppl/lppl-1-3c.txt', 'c1ae6e179a6d28bbd5c483fbacc744acc75e922d598281dc3390aab26126e163']
  ].map(([name, url, expected]) => {
    const section = notice.slice(notice.indexOf(`## ${name}\n`));
    const text = /```text\n([^]*?)\n```/.exec(section)?.[1];
    must(text && sha(text) === expected && section.includes(url), 'font-official-terms-mismatch');
    return { name, url, sha256: expected };
  });
  return { noticesSHA256: sha(notice), fontCount: fonts.length, classes, terms, fonts };
}
export function nodePolicy(exe, distribution) {
  must(path.isAbsolute(exe), 'node-absolute-required');
  const real = fs.realpathSync(exe);
  const info = JSON.parse(command(real, ['-p', 'JSON.stringify({version:process.version,arch:process.arch,platform:process.platform})']));
  must(distribution?.schema === 1 && distribution.version === 'v22.23.5' &&
    info.version === distribution.version && info.arch === distribution.arch && info.platform === distribution.platform, 'node-incompatible');
  const loads = command('/usr/bin/otool', ['-arch', 'arm64', '-l', real]);
  const deps = command('/usr/bin/otool', ['-arch', 'arm64', '-L', real]).split('\n').slice(1).map(l => l.trim().split(' (compatibility')[0]).filter(Boolean);
  const minOS = /\bminos (\d+\.\d+(?:\.\d+)?)/.exec(loads)?.[1] ?? /\bversion (\d+\.\d+(?:\.\d+)?)/.exec(loads)?.[1];
  const number = v => v.split('.').reduce((n, p, i) => n + Number(p) * 100 ** (2 - i), 0);
  must(minOS && number(minOS) <= number(distribution.maximumMinOS), 'node-minOS-incompatible');
  must(deps.every(d => d.startsWith('/usr/lib/') || d.startsWith('/System/Library/')), 'node-external-dylib');
  must(!loads.includes('LC_RPATH'), 'node-external-rpath');
  const license = path.resolve(real, '../../LICENSE');
  must(sha(fs.readFileSync(license)) === distribution.license.sha256, 'node-license-mismatch');
  return { policy: 'portable-bundled', executable: 'node/bin/node', ...info, sha256: sha(fs.readFileSync(real)),
    minOS, effectiveMinOS: minOS, dependencies: deps, hostLibraries: [],
    license: { path: 'node/LICENSE', sha256: distribution.license.sha256 },
    distributionSHA256: sha(encode(distribution)), macOS13Execution: 'unverified' };
}
const filtered = root => inventory(root).filter(f => !['runtime-manifest.json'].includes(f.path));
export function verify(root, exe) {
  must(fs.realpathSync(root) === path.resolve(root), 'stage-symlink');
  root = path.resolve(root);
  const m = json(path.join(root, 'runtime-manifest.json'));
  must(m.schema === 2 && safe(m.entrypoint) && m.entrypoint === 'helper.mjs', 'manifest-schema-entrypoint');
  must(encode(filtered(root)) === encode(m.files), 'payload-tamper-or-missing');
  must(sha(encode(m.files)) === m.payloadSHA256, 'payload-digest-mismatch');
  const n = nodePolicy(exe, json(path.join(root, 'node-distribution.json')));
  must(fs.realpathSync(exe) === fs.realpathSync(path.join(root, m.node.executable)) && encode(n) === encode(m.node), 'node-incompatible');
  must(sha(fs.readFileSync(path.join(root, m.entrypoint))) === m.helperSHA256, 'helper-mismatch');
  const deps = packages(root);
  must(encode(deps) === encode(m.packages), 'package-manifest-mismatch');
  must(encode(fontPreservation(root)) === encode(m.fontPreservation), 'font-preservation-manifest-mismatch');
  must(sha(fs.readFileSync(path.join(root, 'package-lock.json'))) === m.lockSHA256, 'lock-tamper');
  must(m.proof.helperSHA256 === m.helperSHA256, 'proof-helper-mismatch');
  must(encode(m.proof) === encode(json(path.join(root, 'proof-input.json'))), 'proof-manifest-mismatch');
  const report = { schema: 1, status: 'verified', fileCount: m.files.length, packages: deps.length,
    payloadSHA256: sha(encode(m.files)), helperSHA256: m.helperSHA256, lockSHA256: m.lockSHA256, nodeSHA256: n.sha256 };
  must(sha(encode(report)) === m.verifyReportSHA256, 'verify-report-mismatch');
  return report;
}
export function prepare(options) {
  const source = path.resolve(options['runtime-source']), output = path.resolve(options.output), helper = path.resolve(options.helper);
  must(fs.realpathSync(source) === source, 'source-symlink');
  must(output !== source && !output.startsWith(source + '/') && !source.startsWith(output + '/'), 'overlapping-source-output');
  inventory(source); // validates symlinks before copy; archive comparison rejects mutated bytes.
  const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  for (const name of ['package.json', 'package-lock.json', 'THIRD-PARTY-NOTICES.md'])
    must(sha(fs.readFileSync(path.join(source, name))) === sha(fs.readFileSync(path.join(repo, 'tools/flow-reader/native/runtime', name))), 'noncanonical-runtime-input');
  packages(source);
  fontPreservation(source);
  const distributionFile = options['node-distribution'] ?? path.join(repo, 'tools/flow-reader/native/runtime/node-distribution.json');
  const distribution = json(distributionFile);
  must(sha(fs.readFileSync(options.node)) === distribution.executableSHA256, 'node-distribution-bytes');
  nodePolicy(options.node, distribution);
  const proof = options['proof-input'] ? json(options['proof-input']) : {
    helperSHA256: sha(fs.readFileSync(helper)), scope: 'Helper bytes only; no caller-supplied painter/model/fixture acceptance evidence.'
  };
  must(proof.helperSHA256 === sha(fs.readFileSync(helper)), 'proof-helper-mismatch');
  const parent = path.dirname(output); fs.mkdirSync(parent, { recursive: true });
  must(fs.realpathSync(parent) === parent && !fs.lstatSync(helper).isSymbolicLink(), 'output-or-helper-symlink');
  const existing = fs.lstatSync(output, { throwIfNoEntry: false });
  must(!existing || existing.isDirectory(), 'output-type'); // includes dangling symlinks
  const guard = output + '.lock'; fs.mkdirSync(guard);
  const temp = fs.mkdtempSync(path.join(parent, '.runtime-'));
  try {
    // Explicit complete input only; no fallback lookup or network operation.
    for (const name of ['package.json', 'package-lock.json', 'THIRD-PARTY-NOTICES.md', 'node_modules', 'archives', 'acquisition.json'])
      fs.cpSync(path.join(source, name), path.join(temp, name), { recursive: true, verbatimSymlinks: true });
    fs.copyFileSync(helper, path.join(temp, 'helper.mjs'));
    fs.copyFileSync(fileURLToPath(import.meta.url), path.join(temp, 'verify-runtime.mjs'));
    fs.mkdirSync(path.join(temp, 'node/bin'), { recursive: true });
    fs.copyFileSync(options.node, path.join(temp, 'node/bin/node'));
    fs.chmodSync(path.join(temp, 'node/bin/node'), 0o755);
    fs.copyFileSync(path.resolve(options.node, '../../LICENSE'), path.join(temp, 'node/LICENSE'));
    fs.copyFileSync(distributionFile, path.join(temp, 'node-distribution.json'));
    command('/usr/bin/codesign', ['--force', '--sign', options.identity ?? '-', path.join(temp, 'node/bin/node')]);
    const node = nodePolicy(path.join(temp, 'node/bin/node'), distribution);
    write(path.join(temp, 'proof-input.json'), proof);
    const sourceSHA = command('/usr/bin/git', ['-C', repo, 'rev-parse', 'HEAD']).trim();
    const dirty = command('/usr/bin/git', ['-C', repo, 'status', '--porcelain']);
    const sourceFiles = ['scripts/prepare-native-reader-runtime.mjs', 'tools/flow-reader/native/runtime/package.json', 'tools/flow-reader/native/runtime/package-lock.json', 'tools/flow-reader/native/runtime/THIRD-PARTY-NOTICES.md', 'tests/flow-app/native-reader-app/test_runtime.py', 'tests/flow-app/native-reader-app/RuntimeTests.mjs', 'docs/tinymist/dev/native-reader-runtime.typ'].map(p => ({ path: p, sha256: sha(fs.readFileSync(path.join(repo, p))) }));
    const files = filtered(temp), deps = packages(temp), payloadSHA256 = sha(encode(files)), lockSHA256 = sha(fs.readFileSync(path.join(temp, 'package-lock.json')));
    const helperSHA256 = sha(fs.readFileSync(path.join(temp, 'helper.mjs')));
    const report = { schema: 1, status: 'verified', fileCount: files.length, packages: deps.length, payloadSHA256, helperSHA256, lockSHA256, nodeSHA256: node.sha256 };
    const manifest = { schema: 2, entrypoint: 'helper.mjs', source: { sourceSHA, dirty, sourceFiles, baseline: 'cc790bc1778dd7560984eafca93f0d6c052805d4' },
      proof, helperSHA256, lockSHA256, node, packages: deps, files, payloadSHA256,
      fontPreservation: fontPreservation(temp),
      resources: files.filter(f => /mathjax.*(?:dynamic|woff|svg|mathml|liteAdaptor|metrics|input\/tex)/i.test(f.path)).map(f => f.path),
      prepare: { argv: [process.execPath, ...process.argv.slice(1)], exit: 0 }, verifyReportSHA256: sha(encode(report)),
      scope: 'Hash-bound caller helper and portable Node. Package/SRI/font preservation only; no final app/GUI/OS13 acceptance.' };
    write(path.join(temp, 'runtime-manifest.json'), manifest);
    verify(temp, path.join(temp, 'node/bin/node'));
    if (fs.existsSync(output)) {
      must(fs.lstatSync(output).isDirectory(), 'output-type');
      verify(output, path.join(output, 'node/bin/node')); // never overwrite a damaged/unknown existing stage
      // Darwin atomic directory exchange; crash before/after leaves valid output.
      command('/usr/bin/python3', ['-c', 'import ctypes,sys; c=ctypes.CDLL(None,use_errno=True); r=c.renamex_np(sys.argv[1].encode(),sys.argv[2].encode(),2); assert r==0,ctypes.get_errno()', temp, output]);
    } else fs.renameSync(temp, output);
    return report;
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
    fs.rmdirSync(guard);
  }
}
function main() {
  if (process.argv.includes('--help')) { process.stdout.write('Usage: prepare-native-reader-runtime.mjs --runtime-source ROOT --helper FILE --node OFFICIAL_NODE --output ROOT [--proof-input JSON] [--node-distribution JSON] [--identity ID]\n       verify-runtime.mjs --verify ROOT --node ROOT/node/bin/node\n'); return; }
  const o = {};
  for (let i = 2; i < process.argv.length; i += 2) {
    const key = process.argv[i];
    must(['--runtime-source', '--helper', '--node', '--output', '--verify', '--proof-input', '--node-distribution', '--identity'].includes(key) && process.argv[i + 1] && !o[key.slice(2)], 'arguments');
    o[key.slice(2)] = process.argv[i + 1];
  }
  must(o.node && (o.verify ? Object.keys(o).length === 2 : ['runtime-source', 'helper', 'output'].every(k => o[k])), 'arguments');
  const report = o.verify ? verify(o.verify, o.node) : prepare(o);
  process.stdout.write(encode(report));
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(); } catch (e) { process.stderr.write(encode({ status: 'rejected', error: e.message })); process.exitCode = 1; }
}
