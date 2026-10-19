import { ResponsiveMath } from "./rendering/math/renderer.js";
import { MathIdentity, logicalTextIndex } from "./rendering/math/identity.js";
import { mathOverflow } from "./rendering/math/layout.js";
import { loadMathJax } from "./rendering/math/loader.js";

const parameters = new URLSearchParams(location.search);
const fontSize = Number(parameters.get("font") || 18);
const bodyWidth = Number(parameters.get("width") || document.documentElement.clientWidth - 32);
const host = document.querySelector("#reader-document");
host.style.fontSize = `${fontSize}px`;
const progress = document.querySelector("#progress");
const output = document.querySelector("#report");

function prepare(item) {
  const root = document.createElement("div");
  root.innerHTML = item.mathml;
  root.querySelectorAll("script,iframe,object,embed,form,base").forEach((node) => node.remove());
  for (const node of root.querySelectorAll("*")) {
    for (const attribute of [...node.attributes]) {
      if (
        /^on/i.test(attribute.name) ||
        (/^(href|src|xlink:href)$/i.test(attribute.name) &&
          /^\s*javascript:/i.test(attribute.value))
      )
        node.removeAttribute(attribute.name);
    }
  }
  // Match the Reader's note relocation. Their nested mathematical bodies are
  // still composed below, but dynamic paint and note layout are not audited.
  for (const annotation of [...root.querySelectorAll("[data-flow-targets]")]) {
    const note = document.createElement("aside");
    note.append(...annotation.childNodes);
    root.append(note);
    const parent = annotation.parentElement;
    annotation.remove();
    if (parent?.localName === "mtext" && !parent.textContent && !parent.children.length)
      parent.remove();
  }
  return root;
}

async function run() {
  const corpus = await (await fetch("corpus.json")).json();
  const mathjax = await loadMathJax();
  const renderer = new ResponsiveMath(host, {
    preserve: (change) => change(),
    changed() {},
    selectionActive: () => false,
  });
  const records = corpus.roots.filter(
    (item) => !parameters.has("index") || item.index === Number(parameters.get("index")),
  );
  const report = {
    sourceSha256: corpus.sourceSha256,
    rendererFiles: corpus.rendererFiles,
    renderer: "ResponsiveMath.candidate",
    fontSize,
    bodyWidth,
    viewport: innerWidth,
    total: records.length,
    checked: 0,
    expressions: 0,
    promotions: [],
    errors: [],
    identityErrors: [],
    logicalTextChanges: [],
    svgChanges: [],
    overflow: [],
    productionAcceptance: false,
    publicationAndSelectionTested: false,
    dynamicPaintAndFiguresTested: false,
    speechAndAccessibilityTested: false,
  };
  try {
    for (const item of records) {
      const source = prepare(item);
      const maths = [...source.querySelectorAll("math")].filter(
        (node) => !node.parentElement.closest("math"),
      );
      for (const [nested, math] of maths.entries()) {
        const display = math.getAttribute("display") === "block";
        const width = bodyWidth - (display ? fontSize * 0.4 : 0);
        host.style.width = `${width}px`;
        const view = document.createElement("span");
        view.className = "flow-math-view";
        view.dataset.mathDisplay = display ? "block" : "inline";
        const model = new MathIdentity(math, `probe-${item.index}-${nested}`);
        const expectedText = logicalTextIndex(math).text;
        const template = math.cloneNode(true);
        math.replaceWith(view);
        view.append(math);
        host.replaceChildren(view);
        const style = getComputedStyle(view);
        const measurement = { width, fontSize, font: style.font };
        const beforeSvg = template.querySelectorAll("svg").length;
        let result;
        try {
          result = await renderer.candidate(
            { view, model, template, display },
            measurement,
            mathjax,
          );
          const errors = model.bind(result.stage);
          if (errors.length) report.identityErrors.push({ index: item.index, nested, errors });
          // Remove only the staging marker for the logical-text audit. The
          // hidden host retains the same typography and numeric reading width.
          result.stage.classList.remove("flow-math-stage");
          result.stage.style.display = "block";
          if (logicalTextIndex(result.stage).text !== expectedText)
            report.logicalTextChanges.push({ index: item.index, nested });
          const svg = result.stage.querySelectorAll("svg").length;
          if (svg !== beforeSvg)
            report.svgChanges.push({ index: item.index, nested, before: beforeSvg, after: svg });
          if (!display && result.layout === "block")
            report.promotions.push({ index: item.index, nested });
          const overflow = mathOverflow(result.stage, { width });
          if (Math.max(overflow.left, overflow.right) > 1)
            report.overflow.push({ index: item.index, nested, display, width, ...overflow });
          if (parameters.has("preview")) {
            const section = document.createElement("section");
            section.id = `root-${item.index}-${nested}`;
            const label = document.createElement("p");
            label.textContent = `${item.index} / ${nested}`;
            section.append(label, result.stage);
            document.querySelector("#previews").append(section);
            result = null;
          }
        } catch (error) {
          report.errors.push({ index: item.index, nested, error: String(error) });
        } finally {
          result?.stage.remove();
          host.replaceChildren();
        }
        report.expressions++;
      }
      report.checked++;
      if (report.checked % 25 === 0) {
        progress.textContent = `${report.checked} / ${report.total}개 검사`;
        output.textContent = JSON.stringify(report, null, 2);
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
    }
  } finally {
    renderer.clear();
  }
  progress.textContent = `${report.checked} / ${report.total}개 검사 완료`;
  output.textContent = JSON.stringify(report, null, 2);
  document.body.dataset.state = "ready";
}
run().catch((error) => {
  document.body.dataset.state = "error";
  output.textContent = String(error);
});
