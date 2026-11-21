// Existing dependencies only. MathJax is a candidate, never a browser fallback.
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import crypto from 'node:crypto';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../..');
const args = process.argv.slice(2);
function argument(name) { const i = args.indexOf(name); if (i < 0 || !args[i + 1]) throw Error(`missing ${name}`); return args[i + 1]; }
const out = path.resolve(argument('--output'));
if (!out.startsWith('/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/contract/') || fs.existsSync(out)) throw Error('fresh DevSSD output required');
fs.mkdirSync(out, {recursive: true});
const compiler = argument('--compiler');
const sourcePath = path.join(here, 'fixtures/document.typ');
const source = fs.readFileSync(sourcePath, 'utf8');
const nativePath = path.resolve(argument('--native'));
const nativeModel = JSON.parse(fs.readFileSync(nativePath, 'utf8'));
const oracle = path.join(here, 'fixtures/contract.expect.json');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const record = {scope: 'headless object calculation; native consumption is a separate executable; no GUI/AX/fidelity claim',
  fixtureSHA256: hash(Buffer.from(source)), oracleSHA256: hash(fs.readFileSync(oracle)),
  nativeInputSHA256: hash(fs.readFileSync(nativePath)),
  head: spawnSync('git', ['rev-parse', 'HEAD'], {cwd: repo, encoding: 'utf8'}).stdout.trim(),
  compilerWrapperSHA256: hash(fs.readFileSync(compiler)),
  helperSHA256: hash(fs.readFileSync(fileURLToPath(import.meta.url))), node: process.version,
  commands: [], objects: [], mathjax: {status: 'blocked', adopted: false}};
const require = createRequire(path.join(repo, 'package.json'));
const modules = ['@mathjax/src/js/mathjax.js', '@mathjax/src/js/input/mathml.js', '@mathjax/src/js/output/svg.js',
  '@mathjax/src/js/adaptors/liteAdaptor.js', '@mathjax/src/js/handlers/html.js', '@mathjax/mathjax-newcm-font/js/svg.js'];
record.mathjax.modules = modules.map(module => {
  try { const resolved = require.resolve(module); return {module, path: resolved, sha256: hash(fs.readFileSync(resolved))}; }
  catch (error) { return {module, error: error.code}; }
});
const vendor = path.join(repo, 'tools/flow-reader/web/vendor/mathjax-4.1.3');
record.mathjax.vendor = {manifestSHA256: hash(fs.readFileSync(path.join(vendor, 'manifest.json'))),
  licenseSHA256: hash(fs.readFileSync(path.join(vendor, 'LICENSE'))),
  version: '4.1.3', license: 'Apache-2.0', output: 'CHTML',
  nodeMainExists: fs.existsSync(path.join(vendor, 'mathjax/node-main.mjs')),
  svgExists: fs.existsSync(path.join(vendor, 'mathjax/output/svg.js')),
  liteDOMExists: fs.existsSync(path.join(vendor, 'mathjax/adaptors/liteDOM.js'))};
// Probe the advertised vendor Node entry too; resolution metadata is not execution.
try { await import(pathToFileURL(path.join(vendor, 'mathjax/node-main.mjs')).href); record.mathjax.vendorImport = 'loaded'; }
catch (error) { record.mathjax.vendorImport = error.code; }
if (record.mathjax.modules.every(m => m.path)) {
  try {
    const imports = await Promise.all(record.mathjax.modules.map(m => import(pathToFileURL(m.path).href)));
    const [{mathjax}, {MathML}, {SVG}, {liteAdaptor}, {RegisterHTMLHandler}, fontModule] = imports;
    const adaptor = liteAdaptor(); RegisterHTMLHandler(adaptor);
    const font = fontModule.MathJaxNewcmFont || fontModule.NewcmFont;
    if (!font) throw Error('font export unavailable');
    const native = nativeModel;
    const walk = n => [n, ...n.children.flatMap(walk)];
    const math = native.blocks.flatMap(walk).find(n => n.kind === 'math' && n.math.display).math.mathML;
    const document = mathjax.document('', {InputJax: new MathML(), OutputJax: new SVG({fontData: font})});
    for (const width of [320, 640, 960]) {
      const svg = adaptor.outerHTML(document.convert(math, {display: true, em: 18, ex: 9, containerWidth: width}));
      const file = path.join(out, `mathjax-${width}.svg`); fs.writeFileSync(file, svg);
      record.objects.push({id: `mathjax-${width}`, kind: 'mathjax', widthPt: width, fontPt: 18, format: 'svg', path: file, sha256: hash(Buffer.from(svg))});
    }
    record.mathjax.status = 'calculation-pass-native-paint-pending';
  } catch (error) { record.mathjax.reason = `local module probe failed: ${error.name}`; }
} else record.mathjax.reason = 'existing local SVG/liteAdaptor/input/font module set unavailable; no install authorized';
const equation = source.split('\n').find(line => line.startsWith('$ integral_'));
const shape = source.split('\n').find(line => line.startsWith('#let contract-shape ='));
if (!equation || !shape) throw Error('fixture probe objects absent');
for (const width of [320, 640, 960]) {
  for (const [kind, body] of [['math', equation], ['shape', shape + '\n#contract-shape']]) {
    const input = path.join(out, `${kind}-${width}.typ`);
    fs.writeFileSync(input, `#set page(width: ${width}pt, height: auto, margin: 8pt)\n#set text(size: 18pt)\n#set math.equation(numbering: "(1)")\n${body}\n`);
    for (const format of ['svg', 'pdf']) {
      const output = path.join(out, `${kind}-${width}.${format}`);
      const argv = ['compile', '--jobs', '1', input, output];
      const run = spawnSync(compiler, argv, {encoding: 'utf8'});
      record.commands.push({argv: [compiler, ...argv], exit: run.status, stdout: run.stdout, stderr: run.stderr});
      const object = {id: `${kind}-${width}-${format}`, kind, widthPt: width, fontPt: 18, format,
        path: output, compilerExit: run.status, inputSHA256: hash(fs.readFileSync(input)), status: run.status === 0 ? 'calculation-pass-native-paint-pending' : 'blocked'};
      if (run.status === 0) {
        const bytes = fs.readFileSync(output); object.sha256 = hash(bytes);
        if (format === 'svg') object.primitives = [...new Set([...bytes.toString().matchAll(/<([a-zA-Z][\w:-]*)\b/g)].map(m => m[1]))];
      }
      record.objects.push(object);
    }
  }
}
for (const asset of nativeModel.assets.filter(a => a.mime === 'image/svg+xml')) {
  const file = path.join(path.dirname(nativePath), 'assets', asset.id);
  const bytes = fs.readFileSync(file);
  if (hash(bytes) !== asset.sha256) throw Error('imported asset hash mismatch');
  record.objects.push({id: 'imported-figure-' + record.objects.length, kind: 'shape', pipeline: 'accepted-HTML-to-native-importer',
    widthPt: 320, fontPt: 14, format: 'svg', path: file, sha256: hash(bytes)});
}
for (const object of record.objects.filter(o => o.format === 'svg' && fs.existsSync(o.path))) {
  const svg = fs.readFileSync(object.path, 'utf8');
  const w = svg.match(/\bwidth="([0-9.]+)pt"/), h = svg.match(/\bheight="([0-9.]+)pt"/);
  if (w && h) object.viewportPt = [Number(w[1]), Number(h[1])];
}
record.linebreaking = {display: 'compiler width supplied; visual fidelity unverified', inline: 'unsupported: native line breaking/selection/AX requires NA03; browser behavior is not reused'};
record.fonts = {typst: 'existing system/default fonts; SVG may use compiler glyph paths; see primitives', mathjax: 'unavailable unless local font module probe succeeds'};
fs.writeFileSync(path.join(out, 'probe.json'), JSON.stringify(record, null, 2) + '\n');
console.log(JSON.stringify({output: path.join(out, 'probe.json'), mathjax: record.mathjax.status, objects: record.objects.length}));
// Partial blocking is deliberate and must not be reported as a complete object gate.
process.exitCode = record.mathjax.status === 'blocked' || record.objects.some(o => o.compilerExit && o.compilerExit !== 0) ? 2 : 0;
