// Integration checks run against the actual Reader, local renderer, and Typst
// endpoints. This module is exposed only by tests/runtime_fixture.py.
import { MathIdentity, logicalTextIndex } from "/math-identity.js";
import { ResponsiveMath } from "/math-renderer.js";

const report = { checks: [], errors: [] };
const output = document.createElement("pre");
output.id = "runtime-report";
output.style.cssText = "white-space:pre-wrap;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
function show() {
  output.textContent = JSON.stringify(report, null, 2);
}
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  show();
}
async function until(condition, name, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
function visual(root, selector) {
  return [...root.querySelectorAll(selector)].filter((n) => !n.closest("mjx-assistive-mml"));
}
function copy(range) {
  const selection = getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
  const clipboardData = new DataTransfer();
  range.startContainer.parentElement.dispatchEvent(
    new ClipboardEvent("copy", {
      clipboardData,
      bubbles: true,
      cancelable: true,
    }),
  );
  return clipboardData.getData("text/plain");
}
async function lifecycleChecks() {
  const host = document.createElement("div");
  host.style.cssText =
    "position:fixed;top:0;left:0;width:240px;font:18px serif;opacity:0;pointer-events:none";
  host.setAttribute("aria-hidden", "true");
  document.body.append(host);
  let selecting = false;
  const renderer = new ResponsiveMath(host, {
    preserve: (change) => change(),
    changed() {},
    selectionActive: () => selecting,
  });
  const make = () => {
    host.innerHTML =
      '<math display="block"><mi>x</mi><mo>+</mo><mi>y</mi><mo>=</mo><mn>1</mn></math>';
    renderer.prepare(host);
    return [...renderer.records][0];
  };
  const candidate = renderer.candidate.bind(renderer);
  async function delayed(action) {
    let release,
      started = false;
    const gate = new Promise((resolve) => {
      release = resolve;
    });
    renderer.candidate = async (...args) => {
      const result = await candidate(...args);
      started = true;
      await gate;
      return result;
    };
    const rendering = renderer.render();
    await until(() => started, "delayed candidate");
    action();
    release();
    await rendering;
    renderer.candidate = candidate;
  }
  try {
    const old = make();
    await delayed(() => {
      renderer.clear();
      make();
    });
    check(
      "A completed old revision cannot replace the new document",
      !old.view.isConnected && Boolean(host.querySelector(".flow-math-view > math")),
    );
    await renderer.render();
    let record = [...renderer.records][0];
    const previous = record.view.firstElementChild;
    host.style.width = "220px";
    await delayed(() => {
      host.style.width = "200px";
    });
    check(
      "A result measured for an obsolete width is discarded",
      record.view.firstElementChild === previous,
    );
    await renderer.render();
    const atWidth = record.view.firstElementChild;
    host.style.fontSize = "24px";
    await delayed(() => {
      selecting = true;
    });
    check(
      "A selection started during composition keeps the current DOM",
      record.view.firstElementChild === atWidth,
    );
    selecting = false;
    await renderer.render();
    let attempts = 0;
    renderer.candidate = (...args) =>
      ++attempts === 1 ? Promise.reject(new Error("Intentional test failure")) : candidate(...args);
    host.style.width = "180px";
    const beforeFailure = record.view.firstElementChild;
    await renderer.render();
    check(
      "A failed composition retains the last readable equation",
      record.view.dataset.mathState === "error" && record.view.firstElementChild === beforeFailure,
    );
    await until(
      () => record.view.dataset.mathState === "ready",
      "automatic retry without another UI event",
      10000,
    );
    check(
      "A transient composition failure retries automatically",
      attempts === 2 && !host.querySelector(".flow-math-status"),
    );
  } finally {
    renderer.clear();
    host.remove();
  }
}
try {
  await until(
    () => document.querySelector('#long-sum .flow-math-view[data-math-state="ready"]'),
    "initial composition",
  );
  const article = document.querySelector("#reader-document");
  const first = article.querySelector("#long-sum .flow-math-view");
  if (Number(document.querySelector("#reader-size").value) !== 18) {
    const previous = first.firstElementChild;
    while (Number(document.querySelector("#reader-size").value) !== 18)
      document
        .querySelector(
          Number(document.querySelector("#reader-size").value) < 18
            ? "#reader-larger"
            : "#reader-smaller",
        )
        .click();
    await until(
      () => first.firstElementChild !== previous && first.dataset.mathState === "ready",
      "initial 18px composition",
    );
  }
  const doc = new DOMParser().parseFromString(
    await (await fetch("/document.html")).text(),
    "text/html",
  );
  const expected = logicalTextIndex(doc.querySelector("#long-sum math")).text;
  check(
    "Canonical source order survives script DOM reordering",
    logicalTextIndex(first).text === expected,
  );
  const native = doc.querySelector("#long-sum math").cloneNode(true);
  const identity = new MathIdentity(native, "rejection-test");
  const host = document.createElement("div");
  host.append(native);
  check("A native identity can be bound", identity.bind(host).length === 0);
  const prior = identity.tokens[0].points;
  const broken = host.cloneNode(true);
  broken.querySelector("[data-flow-token]").remove();
  check(
    "A rejected candidate preserves the previous binding",
    identity.bind(broken).length > 0 && identity.bound && identity.tokens[0].points === prior,
  );

  const initial = first.firstElementChild;
  let index = logicalTextIndex(first);
  const range = document.createRange();
  range.setStart(...index.points[0].start);
  // Presentation scripts have a different order, so select the full view.
  range.selectNodeContents(first);
  check("Copy emits canonical math once without assistive duplicates", copy(range) === expected);
  const larger = document.querySelector("#reader-larger");
  while (!larger.disabled) larger.click();
  await new Promise((resolve) => setTimeout(resolve, 500));
  check(
    "Font updates do not replace an active text selection",
    first.firstElementChild === initial && !getSelection().isCollapsed,
  );
  getSelection().removeAllRanges();
  await until(
    () => first.firstElementChild !== initial && first.dataset.mathState === "ready",
    "font reflow after selection ends",
  );
  check(
    "The chosen 30px reading size is retained",
    parseFloat(getComputedStyle(first).fontSize) === 30,
  );
  check("Reflow preserves the canonical quotation", logicalTextIndex(first).text === expected);
  first.scrollIntoView({ block: "center" });
  check(
    "One logical marked sum has several visual fragments",
    visual(first, '[data-flow-mark="sum"]').length > 1,
  );
  await until(
    () =>
      visual(first, '[data-flow-mark="sum"]').every((n) => n.dataset.decorationState === "ready") &&
      document.querySelector('.flow-graphic-status[data-graphic-state="ready"]'),
    "fragment decorations and original relationship",
    60000,
  );
  const marks = visual(first, '[data-flow-mark="sum"]');
  check(
    "Every visible marked fragment receives decoration",
    marks.every((n) => n.dataset.flowAnchor),
  );
  report.fragments = marks.map((n) => ({ ...n.getBoundingClientRect().toJSON() }));
  check(
    "Assistive MathML is present without duplicated target IDs",
    first.querySelectorAll("mjx-assistive-mml math").length === 1 &&
      !article.querySelector("mjx-assistive-mml [id]"),
  );
  check(
    "Presentation glyphs are hidden from the accessibility tree",
    first.querySelector('mjx-math[aria-hidden="true"]') !== null,
  );
  check(
    "Derivation rows reflow independently",
    article.querySelectorAll(".flow-derivation > mjx-container").length === 2,
  );
  check("Matrices retain their mathematical table", article.querySelector("mjx-mtable") !== null);
  const ids = [...article.querySelectorAll("[id]")].map((n) => n.id);
  check(
    "Staging and line fragments introduce no duplicate DOM IDs",
    new Set(ids).size === ids.length && !ids.some((id) => id.startsWith("math-stage-")),
  );
  const reference = [...article.querySelectorAll(".flow-math-view")].at(-1);
  reference.scrollIntoView({ block: "center" });
  await until(() => reference.dataset.mathState === "ready", "reference math composition");
  const links = visual(article, '.flow-math-view a[href="#long-sum"]');
  check(
    "References inside math remain keyboard-accessible links",
    links.length === 1 && !links[0].closest('[aria-hidden="true"]'),
  );
  check(
    "All renderer and font requests stay on the Reader origin",
    performance
      .getEntriesByType("resource")
      .filter((e) => /mathjax|woff/.test(e.name))
      .every((e) => new URL(e.name).origin === location.origin && e.responseStatus === 200),
  );
  report.assets = performance
    .getEntriesByType("resource")
    .filter((e) => /vendor/.test(e.name))
    .map((e) => ({ url: e.name, status: e.responseStatus }));
  check(
    "No temporary stage remains in the reading body",
    !document.querySelector(".flow-math-stage"),
  );
  check("Wrapped equation fits its own container", first.scrollWidth <= first.clientWidth + 1);
  const active = article.querySelectorAll('.flow-math-view[data-math-state="error"]');
  check("All composed fixture expressions retain validated tokens", active.length === 0);
  index = logicalTextIndex(first);
  const k = index.text.search(/[k𝑘]/u);
  const letter = String.fromCodePoint(index.text.codePointAt(k));
  const superscript = document.createRange();
  superscript.setStart(...index.points[k].start);
  superscript.setEnd(...index.points[k + letter.length - 1].end);
  check("Copying only the superscript does not include subscripts", copy(superscript) === letter);
  getSelection().removeAllRanges();
  first.scrollIntoView({ block: "center" });
  report.width = innerWidth;
  report.font = getComputedStyle(first).fontSize;
  report.states = [...article.querySelectorAll(".flow-math-view")].map((n) => n.dataset.mathState);
  await lifecycleChecks();
  document.body.dataset.runtimeState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.runtimeState = "error";
}
show();
