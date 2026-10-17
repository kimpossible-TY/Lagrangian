import { logicalTextIndex } from "/math-identity.js";
import { ResponsiveMath } from "/math-renderer.js";

const report = { checks: [], errors: [], measurements: [] };
const output = document.createElement("pre");
output.id = "inline-report";
output.style.cssText = "white-space:pre-wrap;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  output.textContent = JSON.stringify(report, null, 2);
}
async function until(condition, name) {
  const deadline = Date.now() + 30000;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
function copy(view) {
  const range = document.createRange();
  range.selectNodeContents(view);
  getSelection().addRange(range);
  const clipboardData = new DataTransfer();
  view.dispatchEvent(
    new ClipboardEvent("copy", { clipboardData, bubbles: true, cancelable: true }),
  );
  getSelection().removeAllRanges();
  return clipboardData.getData("text/plain");
}
async function widerContainer(source) {
  const host = document.createElement("div");
  host.style.cssText = "position:fixed;left:-100000px;top:0;width:240px;font:18px serif";
  host.setAttribute("aria-hidden", "true");
  host.inert = true;
  host.append(source.cloneNode(true));
  document.body.append(host);
  const renderer = new ResponsiveMath(host, {
    preserve: (change) => change(),
    changed() {},
    selectionActive: () => false,
  });
  try {
    renderer.prepare(host);
    renderer.sync();
    const view = host.querySelector(".flow-math-view");
    await until(() => view.dataset.mathState === "ready", "narrow independent composition");
    check("A narrow container promotes the inline expression", view.dataset.mathLayout === "block");
    const previous = view.firstElementChild;
    host.style.width = "1200px";
    await until(
      () => view.firstElementChild !== previous && view.dataset.mathState === "ready",
      "wide independent composition",
    );
    check(
      "Widening restores the original inline presentation",
      view.dataset.mathLayout === "inline",
    );
  } finally {
    renderer.clear();
    host.remove();
  }
}
try {
  await until(() => document.querySelector("#wide-inline .flow-math-view"), "source content");
  const doc = new DOMParser().parseFromString(
    await (await fetch("/document.html")).text(),
    "text/html",
  );
  const wide = document.querySelector("#wide-inline .flow-math-view");
  const short = document.querySelector("#short-inline .flow-math-view");
  const control = document.querySelector("#control-fraction .flow-math-view");
  const linked = document.querySelector("#linked-inline .flow-math-view");
  const expected = logicalTextIndex(doc.querySelector("#wide-inline math")).text;
  const expectedParagraph = logicalTextIndex(doc.querySelector("#wide-inline")).text;
  for (const font of [18, 30]) {
    const previous = wide.firstElementChild;
    const changed = Number(document.querySelector("#reader-size").value) !== font;
    while (Number(document.querySelector("#reader-size").value) !== font)
      document
        .querySelector(
          Number(document.querySelector("#reader-size").value) < font
            ? "#reader-larger"
            : "#reader-smaller",
        )
        .click();
    wide.scrollIntoView({ block: "center" });
    await until(
      () =>
        [wide, short, control, linked].every((v) => v.dataset.mathState === "ready") &&
        [...wide.querySelectorAll("[data-flow-decoration]")]
          .filter((n) => !n.closest("mjx-assistive-mml"))
          .every((n) => n.dataset.decorationState === "ready") &&
        (!changed || wide.firstElementChild !== previous),
      `${font}px composition`,
    );
    check(`${font}px long inline math composes in the body`, wide.dataset.mathLayout === "block");
    check(`${font}px short mathematics stays inline`, short.dataset.mathLayout === "inline");
    check(
      `${font}px the reading size is preserved`,
      parseFloat(getComputedStyle(wide).fontSize) === font,
    );
    check(
      `${font}px the complete mathematical source is retained`,
      logicalTextIndex(wide).text === expected,
    );
    check(`${font}px copied mathematics remains canonical`, copy(wide) === expected);
    const denominatorSize = (v) =>
      parseFloat(getComputedStyle(v.querySelector("mjx-den mjx-mn")).fontSize);
    check(
      `${font}px inline fraction sizing is preserved`,
      Math.abs(denominatorSize(wide) - denominatorSize(control)) < 0.01,
    );
    check(
      `${font}px assistive mathematics retains inline style`,
      wide.querySelector('mjx-assistive-mml math[displaystyle="false"]') !== null,
    );
    const link = [...linked.querySelectorAll('a[href="#wide-inline"]')].find(
      (n) => !n.closest("mjx-assistive-mml"),
    );
    check(
      `${font}px mathematical links remain accessible`,
      link && !link.closest('[aria-hidden="true"]'),
    );
    const wrapper = wide.closest(".flow-inline-equation");
    check(
      `${font}px the component needs no horizontal scrolling`,
      wrapper.scrollWidth <= wrapper.clientWidth + 1,
    );
    check(
      `${font}px the surrounding sentence retains its source order`,
      logicalTextIndex(document.querySelector("#wide-inline")).text === expectedParagraph,
    );
    const marks = [...wide.querySelectorAll("[data-flow-decoration]")].filter(
      (n) => !n.closest("mjx-assistive-mml"),
    );
    check(
      `${font}px every wrapped marked fragment retains its original paint`,
      marks.length > 1 && marks.every((n) => n.dataset.flowAnchor),
    );
    const bounds = wrapper.getBoundingClientRect();
    const ink = [...wide.querySelectorAll("mjx-c,mjx-utext,mjx-stretchy-h,mjx-stretchy-v")]
      .filter(
        (n) =>
          !n.closest("mjx-assistive-mml") &&
          (!n.closest("mjx-stretchy-h,mjx-stretchy-v") ||
            n.matches("mjx-stretchy-h,mjx-stretchy-v")),
      )
      .flatMap((n) => [...n.getClientRects()]);
    check(
      `${font}px the full vertical mathematics is visible`,
      ink.every((r) => r.top >= bounds.top - 1 && r.bottom <= bounds.bottom + 1),
    );
    report.measurements.push({
      font,
      width: wrapper.clientWidth,
      scroll: wrapper.scrollWidth,
      denominator: denominatorSize(wide),
    });
  }
  await widerContainer(doc.querySelector("#wide-inline math"));
  wide.scrollIntoView({ block: "center" });
  report.width = innerWidth;
  document.body.dataset.inlineState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.inlineState = "error";
}
output.textContent = JSON.stringify(report, null, 2);
