// Run through runtime_fixture.py with fixtures/native-decorations.typ.
import { logicalTextIndex } from "/math-identity.js";
import { prepareNativeDecorations } from "/math-layout.js";

const report = { checks: [], errors: [], measurements: [] };
const output = document.createElement("pre");
output.id = "native-report";
output.style.cssText = "white-space:pre-wrap;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  output.textContent = JSON.stringify(report, null, 2);
}
async function until(condition, name) {
  const deadline = Date.now() + 60000;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
function visual(root, selector) {
  return [...root.querySelectorAll(selector)].filter((node) => !node.closest("mjx-assistive-mml"));
}
try {
  await until(() => document.querySelector("#wide-cancel .flow-math-view"), "accepted source");
  const article = document.querySelector("#reader-document");
  const view = article.querySelector("#wide-cancel .flow-math-view");
  const source = new DOMParser().parseFromString(
    await (await fetch("/document.html")).text(),
    "text/html",
  );
  const expected = logicalTextIndex(source.querySelector("#wide-cancel math")).text;
  check(
    "Source cancellation and overline bodies contain no SVG",
    !source.querySelector("math svg"),
  );
  const enclosure = document.createElement("div");
  enclosure.innerHTML = '<math><menclose notation="box"><mi>x</mi></menclose></math>';
  prepareNativeDecorations(enclosure);
  check("Arbitrary enclosures are never flattened", enclosure.querySelector("menclose") !== null);
  for (const font of [18, 30]) {
    let size = Number(document.querySelector("#reader-size").value);
    const previous = view.firstElementChild;
    const recompose = size !== font;
    while (size !== font) {
      document.querySelector(size < font ? "#reader-larger" : "#reader-smaller").click();
      size = Number(document.querySelector("#reader-size").value);
    }
    view.scrollIntoView({ block: "center" });
    await until(
      () =>
        ["ready", "overflow"].includes(view.dataset.mathState) &&
        (!recompose || view.firstElementChild !== previous) &&
        visual(view, "[data-flow-decoration]").every(
          (node) => node.dataset.decorationState === "ready",
        ) &&
        parseFloat(getComputedStyle(view).fontSize) === font,
      `${font}px native decoration`,
    );
    const fragments = visual(view, "[data-flow-decoration]");
    check(
      `${font}px cancellation retains every canonical term`,
      logicalTextIndex(view).text === expected,
    );
    check(`${font}px wide cancellation breaks into readable fragments`, fragments.length > 1);
    check(
      `${font}px all fragments receive original paint`,
      fragments.every((node) => node.dataset.flowAnchor),
    );
    check(
      `${font}px visual math has no duplicate native strike`,
      !visual(view, "mjx-menclose").length,
    );
    check(
      `${font}px assistive math retains cancellation notation`,
      view.querySelector('mjx-assistive-mml menclose[notation="updiagonalstrike"]') !== null,
    );
    check(
      `${font}px overline remains semantic`,
      view.querySelector("mjx-assistive-mml mover[accent=true]") !== null,
    );
    const overline = visual(view, "mjx-mover[data-flow-overline]")[0];
    check(
      `${font}px the overline spans its complete body`,
      overline?.querySelector("mjx-stretchy-h")?.getBoundingClientRect().width >=
        overline?.querySelector("mjx-base").getBoundingClientRect().width - 1,
    );
    const bounds = view.getBoundingClientRect();
    const glyphs = visual(view, "mjx-c,mjx-utext")
      .filter((node) => !node.closest("mjx-stretchy-h,mjx-stretchy-v"))
      .concat(visual(view, "mjx-stretchy-h,mjx-stretchy-v"))
      .flatMap((node) => [...node.getClientRects()]);
    check(
      `${font}px mathematical text fits the reading width`,
      view.scrollWidth <= view.clientWidth + 1 &&
        glyphs.every((rect) => rect.left >= bounds.left - 1 && rect.right <= bounds.right + 1),
    );
    const range = document.createRange();
    range.selectNodeContents(view);
    getSelection().addRange(range);
    const clipboardData = new DataTransfer();
    view.dispatchEvent(
      new ClipboardEvent("copy", { clipboardData, bubbles: true, cancelable: true }),
    );
    check(
      `${font}px copying retains the source once`,
      clipboardData.getData("text/plain") === expected,
    );
    getSelection().removeAllRanges();
    report.measurements.push({
      font,
      width: bounds.width,
      fragments: fragments.length,
      text: expected,
      left: Math.min(...glyphs.map((rect) => rect.left)) - bounds.left,
      right: Math.max(...glyphs.map((rect) => rect.right)) - bounds.right,
    });
  }
  const custom = article.querySelector("#custom-cancel .flow-math-view");
  custom.scrollIntoView({ block: "center" });
  await until(
    () =>
      custom.dataset.mathState === "ready" &&
      visual(custom, "[data-flow-decoration]").every(
        (node) => node.dataset.decorationState === "ready",
      ),
    "custom cancellation",
  );
  const id = visual(custom, "[data-flow-decoration]")[0].dataset.flowDecoration;
  const svgs = [...custom.closest(".flow-equation").querySelectorAll(".flow-decoration-paint")];
  check(
    "The custom cross retains two dashed red strokes per fragment",
    svgs.length > 0 &&
      svgs.every((svg) => {
        const paths = [...svg.querySelectorAll("path")];
        return (
          paths.length === 2 &&
          paths.every(
            (path) =>
              path.getAttribute("stroke") === "#ff4136" && path.hasAttribute("stroke-dasharray"),
          )
        );
      }),
  );
  report.width = innerWidth;
  report.customId = id;
  view.scrollIntoView({ block: "center" });
  document.body.dataset.nativeState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.nativeState = "error";
}
output.textContent = JSON.stringify(report, null, 2);
