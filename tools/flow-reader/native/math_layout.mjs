/** Pure, bounded MathML or explicit base/AMS TeX -> self-contained SVG metrics. No browser or paint.
 * CLI: node math_layout.mjs --runtime <offline package root>, one JSON on stdin.
 * The trusted launcher MUST deny network (sandbox-exec on macOS), set a deadline
 * and cap stdout. Runtime is configuration, never a document-supplied path.
 * Legacy MathML requests remain supported. TeX has no user macros or loader.
 * No URLs, file inputs, extensions, remote fonts or arbitrary options.
 */
import { createRequire } from 'node:module';
import { readFileSync, realpathSync } from 'node:fs';
import { resolve, sep } from 'node:path';
import { createHash } from 'node:crypto';

const fail = (code) => { throw new Error(code); };
const hash = (s) => createHash('sha256').update(s).digest('hex');
const LIMIT = 8 * 1024 * 1024;
const BATCH_LIMIT = 64 * 1024 * 1024;
const tags = new Set('math mrow mi mn mo ms mtext mspace msup msub msubsup mfrac msqrt mroot mover munder munderover mtable mtr mtd menclose mpadded mphantom semantics annotation mmultiscripts mprescripts'.split(' '));
const attrs = new Set('xmlns display mathvariant scriptlevel displaystyle lspace rspace form stretchy symmetric fence separator accent accentunder notation columnalign rowalign columnspacing rowspacing rowspan columnspan width height depth voffset linethickness encoding'.split(' '));

// A closed vocabulary also rejects dangerous base commands (\\def, \\csname,
// \\newcommand, \\let) before parsing. Unknown commands never become text.
const commands = new Set(('frac dfrac tfrac sqrt over atop choose binom dbinom tbinom ' +
  'left right middle big Big bigg Bigg bigl bigr Bigl Bigr ' +
  'sum prod int iint iiint oint lim sin cos tan log ln exp min max inf sup ' +
  'alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta iota kappa lambda mu nu xi pi varpi rho varrho sigma varsigma tau upsilon phi varphi chi psi omega ' +
  'Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega ' +
  'infty partial nabla pm mp times div cdot le leq ge geq ne neq approx equiv sim to rightarrow leftarrow Rightarrow Leftarrow leftrightarrow mapsto in notin subset supset subseteq supseteq cup cap emptyset forall exists ' +
  'text mathrm mathit mathbf mathbb mathcal mathsf mathtt operatorname boldsymbol ' +
  'overline underline hat widehat bar vec dot ddot tilde widetilde ' +
  'begin end quad qquad ldots cdots vdots ddots lbrace rbrace langle rangle vert Vert lvert rvert lVert rVert ' +
  'displaystyle textstyle scriptstyle scriptscriptstyle').split(/\s+/));
const environments = new Set('matrix pmatrix bmatrix Bmatrix vmatrix Vmatrix smallmatrix cases aligned alignedat gathered split'.split(' '));
function validateTeX(source) {
  if (source.length > 16384 || /[\u0000-\u0008\u000b\u000c\u000e-\u001f%#$]|(?:https?|file|data):|<|>/i.test(source)) fail('tex-policy');
  let depth = 0, tokens = 0;
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (++tokens > 8192) fail('tex-token-limit');
    if (ch === '\\') {
      const m = /^[a-zA-Z]+/.exec(source.slice(i + 1));
      if (m) {
        if (!commands.has(m[0])) fail('tex-command');
        i += m[0].length;
        if (m[0] === 'begin' || m[0] === 'end') {
          const e = /^\{([A-Za-z]+)\}/.exec(source.slice(i + 1));
          if (!e || !environments.has(e[1])) fail('tex-environment');
        }
      } else {
        if (!source[i+1] || !'\\{} ,;:!|_&'.includes(source[i+1])) fail('tex-command');
        i++;
      }
    } else if (ch === '{') { if (++depth > 64) fail('tex-depth'); }
    else if (ch === '}' && --depth < 0) fail('tex-syntax');
  }
  if (depth) fail('tex-syntax');
}

async function main() {
  if (process.argv.length !== 4 || process.argv[2] !== '--runtime') fail('runtime-configuration');
  const root = realpathSync(process.argv[3]);
  const req = createRequire(resolve(root, 'package.json'));
  for (const name of ['@mathjax/src', '@mathjax/mathjax-newcm-font']) {
    const p = JSON.parse(readFileSync(resolve(root, 'node_modules', name, 'package.json')));
    if (p.version !== '4.1.3') fail('runtime-version');
  }
  let raw = '';
  let inputBytes = 0;
  // Decode across chunk boundaries: large batches can split a UTF-8 scalar.
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) {
    inputBytes += Buffer.byteLength(chunk);
    if (inputBytes > BATCH_LIMIT) fail('input-limit');
    raw += chunk;
  }
  const input = JSON.parse(raw);
  const runtime = createRuntime(root, req);
  let output;
  if (input?.kind === 'mathml-batch') {
    if (Object.keys(input).some(k => !['kind', 'items'].includes(k)) ||
        !Array.isArray(input.items) || input.items.length < 1 || input.items.length > 512) fail('input-batch');
    const items = [];
    let bytes = 0;
    for (const item of input.items) {
      if (!item || typeof item !== 'object' || Array.isArray(item) ||
          (item.kind !== undefined && item.kind !== 'mathml')) fail('input-kind');
      const result = await layout(item, root, req, runtime);
      const itemBytes = Buffer.byteLength(JSON.stringify(result));
      if (itemBytes > LIMIT) fail('output-limit');
      bytes += itemBytes + 1;
      if (bytes > BATCH_LIMIT) fail('output-limit');
      items.push(result);
    }
    output = { kind: 'mathml-batch', items };
  } else {
    if (inputBytes > 256 * 1024) fail('input-limit');
    output = await layout(input, root, req, runtime);
  }
  const encoded = JSON.stringify(output);
  if (Buffer.byteLength(encoded) > (input.kind === 'mathml-batch' ? BATCH_LIMIT : LIMIT)) fail('output-limit');
  process.stdout.write(encoded + '\n');
}

function createRuntime(root, req) {
  const { mathjax } = req('@mathjax/src/js/mathjax.js');
  const loaded = new Set();
  mathjax.asyncLoad = (name) => {
    const path = realpathSync(req.resolve(name));
    // MathJax may request only pinned SVG glyph data; never input extensions.
    const fontRoot = realpathSync(resolve(root, 'node_modules/@mathjax/mathjax-newcm-font'));
    if (!path.startsWith(fontRoot + sep + 'cjs' + sep + 'svg' + sep + 'dynamic' + sep) ||
        !/^[a-zA-Z0-9_-]+\.js$/.test(path.split(sep).at(-1))) fail('external-module');
    loaded.add(path.slice(root.length + 1));
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
  return { mathjax, adaptor, outputJax, engine, loaded };
}

async function layout(input, root, req, runtime) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) fail('input-value');
  if (Buffer.byteLength(JSON.stringify(input)) > 256 * 1024) fail('input-limit');
  if (Object.keys(input).some(k => !['kind', 'mathML', 'tex', 'display', 'width', 'fontSize', 'font', 'context'].includes(k))) fail('input-field');
  const kind = input.kind ?? 'mathml';
  const texPackages = ['base', 'ams'];
  if (!['mathml', 'tex'].includes(kind) ||
      (kind === 'mathml' && ('tex' in input || 'display' in input)) ||
      (kind === 'tex' && ('mathML' in input || typeof input.display !== 'boolean'))) fail('input-kind');
  const source = kind === 'tex' ? input.tex : input.mathML;
  if (typeof source !== 'string' || !source.trim() || Buffer.byteLength(source) > 65536 ||
      !Number.isFinite(input.width) || input.width < 16 || input.width > 8192 ||
      !Number.isFinite(input.fontSize) || input.fontSize < 8 || input.fontSize > 96 ||
      input.font !== 'MathJaxNewcm' || !input.context ||
      !['light', 'dark'].includes(input.context.theme) ||
      !Number.isSafeInteger(input.context.generation) || input.context.generation < 0 ||
      !/^[A-Za-z0-9_.:-]{1,128}$/.test(input.context.revision ?? '') ||
      Object.keys(input.context).some(k => !['theme', 'generation', 'revision'].includes(k))) fail('input-value');
  if (kind === 'mathml') {
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
  } else {
    validateTeX(source);
  }
  const { mathjax, adaptor, outputJax, engine, loaded } = runtime;
  // A retry or an earlier formula must never supply this item's wrapper.
  outputJax.lastWrapper = undefined;
  let mathML = source.trim(), semanticText = '', display = false;
  if (kind === 'tex') {
    const { TeX } = req('@mathjax/src/js/input/tex.js');
    req('@mathjax/src/js/input/tex/ams/AmsConfiguration.js');
    const { SerializedMmlVisitor } = req('@mathjax/src/js/core/MmlTree/SerializedMmlVisitor.js');
    const { STATE } = req('@mathjax/src/js/core/MathItem.js');
    const tex = new TeX({ packages: texPackages, maxBuffer: 65536,
      maxTemplateSubtitutions: 1000, formatError: () => fail('tex-syntax') });
    const compiler = mathjax.document('', { InputJax: tex, OutputJax: outputJax });
    const tree = compiler.convert(source.trim(), { display: input.display, end: STATE.COMPILED });
    let nodes = 0;
    function describe(n, depth = 0) {
      if (++nodes > 4096 || depth > 64) fail('semantic-limit');
      const children = n.childNodes ?? [];
      const c = children.map(x => describe(x, depth + 1));
      if (n.kind === 'text') return n.getText();
      const names = { mfrac: 'fraction', msqrt: 'square root', mroot: 'root',
        msup: 'superscript', msub: 'subscript', msubsup: 'subscript and superscript',
        mtable: 'matrix', mtr: 'row', mtd: 'cell', munderover: 'under and over',
        munder: 'under', mover: 'over' };
      if (n.kind === 'merror') fail('tex-syntax');
      return names[n.kind] ? names[n.kind] + '(' + c.join(', ') + ')' : c.join(' ');
    }
    semanticText = describe(tree).replace(/\s+/g, ' ').trim();
    mathML = new SerializedMmlVisitor().visitTree(tree);
    if (Buffer.byteLength(mathML) > 65536 || Buffer.byteLength(semanticText) > 65536) fail('semantic-limit');
    display = input.display;
  } else {
    display = /<math\b[^>]*\bdisplay\s*=\s*['"]block['"]/.test(mathML);
  }
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
  function cleanSVG(svg) {
    return svg.replace(/\sstyle="([^"]*)"/g, (_match, style) => {
      // MathJax emits unitless zero for glyphs without descent (e.g. Ж).
      if (!/^vertical-align:\s*(?:0|-?[0-9.]+ex);?$/.test(style)) fail('unsupported-svg-style');
      return '';
    });
  }
  async function convert(mml) {
    const node = await mathjax.handleRetriesFor(() => engine.convert(mml, {
      display, em: input.fontSize, ex: input.fontSize / 2,
      containerWidth: input.width, scale: 1
    }));
    const svgNode = adaptor.firstChild(node);
    let svg = adaptor.outerHTML(svgNode);
    if (/mjx-merror|<text|<image|<use|href=|url\(|<foreignObject/i.test(svg)) fail('unsupported-glyph-or-resource');
    const viewBox = adaptor.getAttribute(svgNode, 'viewBox').split(/\s+/).map(Number);
    if (viewBox.length !== 4 || !viewBox.every(Number.isFinite) || viewBox[2] <= 0 || viewBox[3] <= 0) fail('output-metrics');
    // Include the baseline in the native box. Glyph ink such as x can end
    // above zero; a negative descent is valid SVG ink but invalid native metrics.
    const top = Math.min(0, viewBox[1]), bottom = Math.max(0, viewBox[1] + viewBox[3]);
    viewBox[1] = top; viewBox[3] = bottom - top;
    adaptor.setAttribute(svgNode, 'viewBox', viewBox.join(' '));
    svg = adaptor.outerHTML(svgNode);
    // MathJax SVG coordinates are 1000/em; baseline is y=0 in viewBox.
    const width = viewBox[2] * input.fontSize / 1000;
    const ascent = -viewBox[1] * input.fontSize / 1000;
    const descent = (viewBox[1] + viewBox[3]) * input.fontSize / 1000;
    svg = cleanSVG(svg);
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
      const svg = cleanSVG(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${start * 1000} ${-h * 1000} ${w * 1000} ${(h + d) * 1000}"><g fill="currentColor" stroke="currentColor" stroke-width="0" transform="scale(1,-1)">${body}</g></svg>`);
      if (/<text|<image|<use|href=|url\(|style=/i.test(svg)) fail('unsupported-glyph-or-resource');
      fragments.push({ svg, width: w * input.fontSize, ascent: h * input.fontSize, descent: d * input.fontSize });
    }
    if (Math.abs(x * input.fontSize - whole.width) > input.fontSize * 0.001) fail('unsupported-wrapper-advance');
  }
  const output = { version: 1, inputHash: hash(source), context: input.context,
    font: input.font, fontSize: input.fontSize, width: input.width, whole, fragments,
    diagnostics: fragments.some(f => f.width > input.width) ? ['indivisible-math-overflow'] : [],
    runtime: { mathjax: '4.1.3', newcm: '4.1.3', ...(kind === 'tex' ? { inputPackages: texPackages } : {}), loaded: [...loaded],
      moduleFiles: Object.keys(req.cache).filter(p => p.startsWith(root + sep)).map(p => p.slice(root.length + 1)).sort() } };
  if (kind === 'tex') Object.assign(output, { kind, normalizedTeX: source.trim(), normalizedMathML: mathML, semanticText, display });
  return output;
}
main().catch(error => {
  const allowed = /^[a-z][a-z0-9-]{0,64}$/.test(error.message ?? '') ? error.message : 'math-runtime-failure';
  process.stderr.write(JSON.stringify({ status: 'unsupported', code: allowed }) + '\n');
  process.exitCode = 2;
});
