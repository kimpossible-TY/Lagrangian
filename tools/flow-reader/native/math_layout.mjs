/** Pure, bounded MathML -> self-contained SVG metrics. No browser or paint.
 * CLI: node math_layout.mjs --runtime <offline package root>, one JSON on stdin.
 * The trusted launcher MUST deny network (sandbox-exec on macOS), set a deadline
 * and cap stdout. Runtime is configuration, never a document-supplied path.
 * No TeX, URLs, file inputs, extensions, remote fonts or arbitrary options.
 */
import { createRequire } from 'node:module';
import { readFileSync, realpathSync } from 'node:fs';
import { resolve, sep } from 'node:path';
import { createHash } from 'node:crypto';

const fail = (code) => { throw new Error(code); };
const hash = (s) => createHash('sha256').update(s).digest('hex');
const LIMIT = 8 * 1024 * 1024;
const tags = new Set('math mrow mi mn mo ms mtext mspace msup msub msubsup mfrac msqrt mroot mover munder munderover mtable mtr mtd menclose mpadded mphantom semantics annotation'.split(' '));
const attrs = new Set('xmlns display mathvariant scriptlevel displaystyle lspace rspace form stretchy symmetric fence separator accent accentunder notation columnalign rowalign columnspacing rowspacing rowspan columnspan width height depth voffset linethickness encoding'.split(' '));

async function main() {
  if (process.argv.length !== 4 || process.argv[2] !== '--runtime') fail('runtime-configuration');
  const root = realpathSync(process.argv[3]);
  const req = createRequire(resolve(root, 'package.json'));
  for (const name of ['@mathjax/src', '@mathjax/mathjax-newcm-font']) {
    const p = JSON.parse(readFileSync(resolve(root, 'node_modules', name, 'package.json')));
    if (p.version !== '4.1.3') fail('runtime-version');
  }
  let raw = '';
  for await (const chunk of process.stdin) {
    raw += chunk.toString('utf8');
    if (Buffer.byteLength(raw) > 256 * 1024) fail('input-limit');
  }
  const input = JSON.parse(raw);
  if (Object.keys(input).some(k => !['mathML', 'width', 'fontSize', 'font', 'context'].includes(k))) fail('input-field');
  if (typeof input.mathML !== 'string' || input.mathML.length > 65536 ||
      !Number.isFinite(input.width) || input.width < 16 || input.width > 8192 ||
      !Number.isFinite(input.fontSize) || input.fontSize < 8 || input.fontSize > 96 ||
      input.font !== 'MathJaxNewcm' || !input.context ||
      !['light', 'dark'].includes(input.context.theme) ||
      !Number.isSafeInteger(input.context.generation) || input.context.generation < 0 ||
      !/^[A-Za-z0-9_.:-]{1,128}$/.test(input.context.revision ?? '') ||
      Object.keys(input.context).some(k => !['theme', 'generation', 'revision'].includes(k))) fail('input-value');
  // Validate XML syntax before the permissive liteDOM parser. Only predefined
  // entities/numeric scalars and quoted, allowlisted attributes are accepted.
  if (/<!|<\?|&(?!amp;|lt;|gt;|quot;|apos;|#\d+;|#x[0-9a-fA-F]+;)/.test(input.mathML)) fail('mathml-xml');
  const stack = []; let count = 0, position = 0;
  for (const match of input.mathML.matchAll(/<([^<>]+)>/g)) {
    const gap = input.mathML.slice(position, match.index);
    if (gap.includes('<') || (!stack.length && gap.trim())) fail('mathml-xml');
    if (gap.trim() && !['mi', 'mn', 'mo', 'ms', 'mtext', 'annotation'].includes(stack.at(-1))) fail('mathml-text');
    position = match.index + match[0].length;
    const part = match[1];
    if (part.startsWith('/')) {
      if (stack.pop() !== part.slice(1).trim()) fail('mathml-xml');
      continue;
    }
    const parsed = /^([a-z]+)((?:\s+[\w-]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)$/.exec(part);
    if (!parsed || !tags.has(parsed[1]) || ++count > 4096 || stack.length > 64) fail('mathml-element');
    const seen = new Set();
    for (const a of parsed[2].matchAll(/([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) {
      const value = a[2] ?? a[3];
      if (!attrs.has(a[1]) || seen.has(a[1]) || /[<>]|url\(|https?:|file:|data:/i.test(value) &&
          !(a[1] === 'xmlns' && value === 'http://www.w3.org/1998/Math/MathML')) fail('mathml-attribute');
      if (a[1] === 'xmlns' && value !== 'http://www.w3.org/1998/Math/MathML') fail('mathml-namespace');
      seen.add(a[1]);
    }
    if (!stack.length && (count !== 1 || parsed[1] !== 'math')) fail('mathml-root');
    if (!parsed[3]) stack.push(parsed[1]);
  }
  if (stack.length || !count || input.mathML.slice(position).trim()) fail('mathml-xml');
  const { mathjax } = req('@mathjax/src/js/mathjax.js');
  const loaded = [];
  mathjax.asyncLoad = (name) => {
    const path = realpathSync(req.resolve(name));
    if (!path.startsWith(root + sep)) fail('external-module');
    loaded.push(path.slice(root.length + 1));
    return req(path);
  };
  mathjax.asyncIsSynchronous = true;
  const { MathML } = req('@mathjax/src/js/input/mathml.js');
  const { SVG } = req('@mathjax/src/js/output/svg.js');
  const { liteAdaptor } = req('@mathjax/src/js/adaptors/liteAdaptor.js');
  const { RegisterHTMLHandler } = req('@mathjax/src/js/handlers/html.js');
  const { MathJaxNewcmFont } = req('@mathjax/mathjax-newcm-font/js/svg.js');
  const adaptor = liteAdaptor();
  RegisterHTMLHandler(adaptor);
  // The pinned SVG wrapper exposes the same advances and DOM paths used by
  // MathJax's complete formula. Capture them once; fragment re-typesetting can
  // change TeX atom spacing and is deliberately avoided.
  class CapturingSVG extends SVG {
    processMath(wrapper, parent) { super.processMath(wrapper, parent); this.lastWrapper = wrapper; }
  }
  const outputJax = new CapturingSVG({ fontCache: 'none', font: new MathJaxNewcmFont() });
  const engine = mathjax.document('', { InputJax: new MathML(), OutputJax: outputJax });
  const mathML = input.mathML.trim();
  const dom = adaptor.parse(mathML, 'text/html');
  const math = adaptor.firstChild(adaptor.body(dom));
  // Native line flow may break only at top-level additive/relation operators.
  // Fractions, roots, scripts, fences and matrix rows stay indivisible. No claim
  // of general TeX/MathML linebreaking: overflow is an explicit diagnostic.
  let row = math;
  const wrappers = [];
  while (adaptor.childNodes(row).length === 1 && adaptor.kind(adaptor.firstChild(row)) === 'mrow') {
    row = adaptor.firstChild(row); wrappers.push(adaptor.outerHTML(row).match(/^<mrow[^>]*>/)[0]);
  }
  const children = adaptor.childNodes(row).filter(child => adaptor.kind(child) !== '#text');
  const canSplit = !/scriptlevel\s*=|displaystyle\s*=\s*['"]false['"]/.test(mathML) && wrappers.every(w => /^<mrow>$/u.test(w));
  const parts = []; let part = [];
  let fences = 0;
  for (const [index, child] of children.entries()) {
    const text = adaptor.textContent(child);
    if (adaptor.kind(child) === 'mo' && /^[([{⟨]$/.test(text)) fences++;
    if (canSplit && !fences && adaptor.kind(child) === 'mo' && adaptor.getAttribute(child, 'form') !== 'prefix' && /^[+=−-]$/.test(text) && part.length) {
      parts.push(part); part = [];
    }
    part.push(index);
    if (adaptor.kind(child) === 'mo' && /^[)\]}⟩]$/.test(text)) fences = Math.max(0, fences - 1);
  }
  if (part.length) parts.push(part);
  if (parts.length > 256) fail('fragment-limit');
  async function convert(mml) {
    const node = await mathjax.handleRetriesFor(() => engine.convert(mml, {
      display: false, em: input.fontSize, ex: input.fontSize / 2,
      containerWidth: input.width, scale: 1
    }));
    const svgNode = adaptor.firstChild(node);
    let svg = adaptor.outerHTML(svgNode);
    if (/mjx-merror|<text|<image|<use|href=|url\(|<foreignObject/i.test(svg)) fail('unsupported-glyph-or-resource');
    const viewBox = adaptor.getAttribute(svgNode, 'viewBox').split(/\s+/).map(Number);
    if (viewBox.length !== 4 || !viewBox.every(Number.isFinite) || viewBox[2] <= 0 || viewBox[3] <= 0) fail('output-metrics');
    // MathJax SVG coordinates are 1000/em; baseline is y=0 in viewBox.
    const width = viewBox[2] * input.fontSize / 1000;
    const ascent = -viewBox[1] * input.fontSize / 1000;
    const descent = (viewBox[1] + viewBox[3]) * input.fontSize / 1000;
    svg = svg.replace(/\sstyle="([^"]*)"/g, (_match, style) => {
      if (!/^vertical-align:\s*-?[0-9.]+ex;?$/.test(style)) fail('unsupported-svg-style');
      return '';
    });
    return { svg, width, ascent, descent };
  }
  const whole = await convert(mathML.replace(/^(<math(?:\s[^>]*)?>)([\s\S]*)(<\/math>)$/, '$1<mrow>$2</mrow>$3'));
  const fragments = [];
  if (parts.length <= 1) fragments.push(whole);
  else {
    let wrapper = outputJax.lastWrapper;
    while (wrapper.childNodes.length === 1 && ['mrow', 'inferredMrow'].includes(wrapper.childNodes[0].node.kind)) wrapper = wrapper.childNodes[0];
    if (wrapper.childNodes.length !== children.length) fail('unsupported-wrapper-structure');
    let x = 0;
    for (const indices of parts) {
      const start = x; let h = 0, d = 0, body = '';
      for (const i of indices) {
        const child = wrapper.childNodes[i], box = child.getOuterBBox();
        if (child.node.kind !== adaptor.kind(children[i]) || child.dom?.length !== 1) fail('unsupported-wrapper-structure');
        x += (box.L + box.w + box.R) * box.rscale;
        h = Math.max(h, box.h * box.rscale); d = Math.max(d, box.d * box.rscale);
        body += adaptor.outerHTML(child.dom[0]);
      }
      const w = x - start;
      if (![start, w, h, d].every(Number.isFinite) || w <= 0 || h + d <= 0) fail('output-metrics');
      const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${start * 1000} ${-h * 1000} ${w * 1000} ${(h + d) * 1000}"><g fill="currentColor" stroke="currentColor" stroke-width="0" transform="scale(1,-1)">${body}</g></svg>`;
      if (/<text|<image|<use|href=|url\(|style=/i.test(svg)) fail('unsupported-glyph-or-resource');
      fragments.push({ svg, width: w * input.fontSize, ascent: h * input.fontSize, descent: d * input.fontSize });
    }
    if (Math.abs(x * input.fontSize - whole.width) > input.fontSize * 0.001) fail('unsupported-wrapper-advance');
  }
  const output = { version: 1, inputHash: hash(input.mathML), context: input.context,
    font: input.font, fontSize: input.fontSize, width: input.width, whole, fragments,
    diagnostics: fragments.some(f => f.width > input.width) ? ['indivisible-math-overflow'] : [],
    runtime: { mathjax: '4.1.3', newcm: '4.1.3', loaded: [...new Set(loaded)],
      moduleFiles: Object.keys(req.cache).filter(p => p.startsWith(root + sep)).map(p => p.slice(root.length + 1)).sort() } };
  const encoded = JSON.stringify(output);
  if (Buffer.byteLength(encoded) > LIMIT) fail('output-limit');
  process.stdout.write(encoded + '\n');
}
main().catch(error => {
  const allowed = /^[a-z][a-z0-9-]{0,64}$/.test(error.message ?? '') ? error.message : 'math-runtime-failure';
  process.stderr.write(JSON.stringify({ status: 'unsupported', code: allowed }) + '\n');
  process.exitCode = 2;
});
