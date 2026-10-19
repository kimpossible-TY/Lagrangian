// Standalone corpus probe. This never changes the live Reader or source files.
const main = document.querySelector("main");
const progress = document.querySelector("#progress");
const reportNode = document.querySelector("#report");
const parameters = new URLSearchParams(location.search);
const fontSize = Number(parameters.get("font") || 18);
document.body.style.fontSize = `${fontSize}px`;
const identities = new WeakMap();

function text(root) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) =>
      node.parentElement.closest("svg,.label")
        ? NodeFilter.FILTER_REJECT
        : NodeFilter.FILTER_ACCEPT,
  });
  let result = "";
  for (let node = walker.nextNode(); node; node = walker.nextNode()) result += node.data;
  // MathJax adds invisible function/application operators to presentation text.
  return result.replace(/[\s\u2061-\u2064]/g, "");
}

function prepare(item) {
  const section = document.createElement("section");
  section.className = "equation";
  section.id = `equation-${item.index}`;
  section.dataset.index = item.index;
  section.innerHTML = item.mathml;
  section.querySelectorAll("script,iframe,object,embed,form,base").forEach((n) => n.remove());
  for (const node of section.querySelectorAll("*")) {
    for (const attribute of [...node.attributes]) {
      if (
        /^on/i.test(attribute.name) ||
        (/^(href|src|xlink:href)$/i.test(attribute.name) &&
          /^\s*javascript:/i.test(attribute.value))
      )
        node.removeAttribute(attribute.name);
    }
  }
  // MathJax requires an HTML integration wrapper around foreign SVG tokens.
  for (const svg of section.querySelectorAll("math mtext > svg")) {
    const span = document.createElement("span");
    svg.replaceWith(span);
    span.append(svg);
  }
  // Match the Reader's visible note relocation before measuring mathematics.
  // Preserve the note bodies below the expression; do not count prose stuffed
  // into an unbreakable MathML token as an equation layout limitation.
  const notes = document.createElement("aside");
  notes.className = "probe-notes";
  for (const annotation of [...section.querySelectorAll("[data-flow-targets]")]) {
    const note = document.createElement("div");
    note.dataset.flowTargets = annotation.dataset.flowTargets;
    note.append(...annotation.childNodes);
    if (note.childNodes.length) notes.append(note);
    const parent = annotation.parentElement;
    annotation.remove();
    if (parent?.localName === "mtext" && !parent.textContent && !parent.children.length)
      parent.remove();
  }
  if (notes.children.length) section.append(notes);
  const label = document.createElement("p");
  label.className = "label";
  label.textContent = `식 ${item.index + 1}`;
  section.prepend(label);
  return section;
}

async function run() {
  const { splitDerivations, prepareNativeDecorations, restoreNativeDecorations, mathOverflow } =
    await import("./rendering/math/layout.js");
  const { MathIdentity, logicalTextIndex } = await import("./rendering/math/identity.js");
  await MathJax.startup.promise;
  const response = await fetch(
    parameters.get("source") === "baseline" ? "./baseline-corpus.json" : "./corpus.json",
  );
  if (!response.ok) throw new Error(`Corpus HTTP ${response.status}`);
  const corpus = await response.json();
  const selected = parameters.has("index") ? Number(parameters.get("index")) : null;
  const records = corpus.roots.filter((item) =>
    selected === null
      ? parameters.get("scope") === "all" || item.display === "block"
      : item.index === selected,
  );
  const report = {
    sourceSha256: corpus.sourceSha256,
    mathjaxVersion: corpus.mathjaxVersion,
    scope:
      selected === null
        ? parameters.get("scope") === "all"
          ? "all outer math roots"
          : "all display math roots"
        : `root ${selected}`,
    viewport: innerWidth,
    fontSize,
    total: records.length,
    checked: 0,
    errors: [],
    splitDerivations: 0,
    compositionChanges: [],
    overflow: [],
    textChanges: [],
    svgChanges: [],
    markerChanges: [],
    decorationChanges: [],
    identityErrors: [],
    logicalTextChanges: [],
    logicalMarks: 0,
    visualMarkFragments: 0,
    // These are intentionally separate from a visual/semantic acceptance result.
    productionAcceptance: false,
    speechAndAccessibilityTested: false,
  };
  const batchSize = 25;
  for (let i = 0; i < records.length; i += batchSize) {
    MathJax.typesetClear([main]);
    main.replaceChildren(...records.slice(i, i + batchSize).map(prepare));
    const sections = [...main.children];
    for (const section of sections) {
      section.dataset.readerKey = `probe-${section.dataset.index}`;
      const records = [];
      if (parameters.get("identity") === "1") {
        for (const math of [...section.querySelectorAll("math")].filter(
          (n) => !n.parentElement.closest("math"),
        )) {
          const view = document.createElement(
            math.getAttribute("display") === "block" ? "div" : "span",
          );
          view.className = "flow-math-probe";
          math.replaceWith(view);
          view.append(math);
          records.push({
            view,
            model: new MathIdentity(math, `probe-${section.dataset.index}-${records.length}`),
          });
        }
      }
      identities.set(section, records);
    }
    const before = sections.map((node) => ({
      text: text(node),
      logicalText: logicalTextIndex(node).text,
      svg: node.querySelectorAll("svg").length,
      decorations: [...node.querySelectorAll("[data-flow-decoration]")].map(
        (n) => n.dataset.flowDecoration,
      ),
      markers: [...node.querySelectorAll("[data-flow-mark]")].map((n) => n.dataset.flowMark),
    }));
    if (parameters.get("rows") === "1") {
      for (const node of sections) {
        const before = text(node);
        report.splitDerivations += splitDerivations(node);
        if (text(node) !== before) report.compositionChanges.push(Number(node.dataset.index));
      }
    }
    prepareNativeDecorations(main);
    await MathJax.typesetPromise([main]);
    restoreNativeDecorations(main);
    await document.fonts.ready;
    sections.forEach((node, index) => {
      const id = Number(node.dataset.index);
      for (const { view, model } of identities.get(node)) {
        const errors = model.bind(view);
        if (errors.length) report.identityErrors.push({ index: id, errors });
        report.logicalMarks += model.marks.length;
        report.visualMarkFragments += model.marks.reduce(
          (sum, mark) => sum + mark.fragments.length,
          0,
        );
      }
      if (
        parameters.get("identity") === "1" &&
        logicalTextIndex(node).text !== before[index].logicalText
      ) {
        report.logicalTextChanges.push({
          index: id,
          before: before[index].logicalText,
          after: logicalTextIndex(node).text,
        });
      }
      const errors = [...node.querySelectorAll("mjx-merror")].map((n) =>
        n.getAttribute("data-mjx-error"),
      );
      if (errors.length) report.errors.push({ index: id, errors });
      const overflow = mathOverflow(node);
      if (Math.max(overflow.left, overflow.right) > 1) {
        report.overflow.push({
          index: id,
          available: node.clientWidth,
          required: node.scrollWidth,
          left: overflow.left,
          right: overflow.right,
        });
      }
      const actual = text(node);
      if (actual !== before[index].text)
        report.textChanges.push({ index: id, before: before[index].text, after: actual });
      const svg = node.querySelectorAll("svg").length;
      if (svg !== before[index].svg)
        report.svgChanges.push({ index: id, before: before[index].svg, after: svg });
      const decorations = [...node.querySelectorAll("[data-flow-decoration]")].map(
        (n) => n.dataset.flowDecoration,
      );
      if (JSON.stringify(decorations) !== JSON.stringify(before[index].decorations))
        report.decorationChanges.push({
          index: id,
          before: before[index].decorations,
          after: decorations,
        });
      const markers = [...node.querySelectorAll("[data-flow-mark]")].map((n) => n.dataset.flowMark);
      if (JSON.stringify(markers) !== JSON.stringify(before[index].markers)) {
        report.markerChanges.push({ index: id, before: before[index].markers, after: markers });
      }
    });
    report.checked += sections.length;
    progress.textContent = `${report.checked} / ${report.total}개 수식 검사`;
    reportNode.textContent = JSON.stringify(report, null, 2);
    // Yield between batches without relying on animation frames in a hidden tab.
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  document.body.dataset.state = "ready";
}
run().catch((error) => {
  document.body.dataset.state = "error";
  progress.textContent = "검증 실패";
  reportNode.textContent = String(error);
});
