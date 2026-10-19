import { logicalTextIndex } from "/rendering/math/identity.js";
import { mathOverflow } from "/rendering/math/layout.js";

// This is not an iPhone pinch test. The synthetic resize below isolates WebKit's
// innerWidth change without a layout-width change; CUA drives real width changes.
const testKey = "flow-reader-viewport-test:" + location.search;
const saved = JSON.parse(sessionStorage.getItem(testKey) || "null");
const report = saved ?? { checks: [], errors: [], measurements: [] };
const output = document.createElement("pre");
output.id = "viewport-report";
output.style.cssText =
  "white-space:pre-wrap;overflow-wrap:anywhere;font:13px monospace;margin:16px";
document.body.append(output);
function publish() {
  output.textContent = JSON.stringify(report, null, 2);
}
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  publish();
}
async function until(condition, name) {
  const deadline = Date.now() + 90000;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${name}`);
    await new Promise((resolve) => setTimeout(resolve, 40));
  }
}
const frame = () => new Promise(requestAnimationFrame);
const size = () => Number(document.querySelector("#reader-size").value);
const target = () => document.querySelector("#long-sum .flow-math-view");
function measurement(phase) {
  const article = document.querySelector("#reader-document");
  report.measurements.push({
    phase,
    innerWidth,
    layoutWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth,
    articleWidth: article.getBoundingClientRect().width,
    font: getComputedStyle(article).fontSize,
    visualWidth: visualViewport.width,
    visualScale: visualViewport.scale,
  });
}
async function run() {
  await until(() => target()?.dataset.mathState === "ready", "reading math");
  const article = document.querySelector("#reader-document");
  const source = new DOMParser().parseFromString(
    await (await fetch("/document.html")).text(),
    "text/html",
  );
  const canonical = logicalTextIndex(source.querySelector("#long-sum math")).text;
  if (!saved) {
    check(
      "Fresh and legacy settings start at 13 CSS pixels",
      size() === 13 && getComputedStyle(article).fontSize === "13px",
    );
    check(
      "The 13px minimum disables only the smaller-text button",
      document.querySelector("#reader-smaller").disabled &&
        !document.querySelector("#reader-larger").disabled,
    );
    const viewport = document.querySelector('meta[name="viewport"]').content;
    check(
      "Viewport uses device width and a 1x floor with no automatic page shrinking",
      /width=device-width/.test(viewport) &&
        /initial-scale=1(?:,|$)/.test(viewport) &&
        /minimum-scale=1(?:,|$)/.test(viewport) &&
        /shrink-to-fit=no/.test(viewport),
    );
    check("User enlargement remains available", !/user-scalable=no|maximum-scale/.test(viewport));
    check(
      "The selected font is not replaced by Safari text inflation",
      getComputedStyle(article).webkitTextSizeAdjust === "100%",
    );
    measurement("initial");

    window.scrollTo(0, 0);
    await frame();
    await frame();
    const descriptor = Object.getOwnPropertyDescriptor(window, "innerWidth");
    const beforeWidth = article.getBoundingClientRect().width;
    const originalWidth = innerWidth;
    try {
      // A fresh scroll must not be undone using the previous queued anchor when
      // a pinch-like resize reports a different innerWidth in the same frame.
      window.scrollBy(0, 31);
      const before = scrollY;
      Object.defineProperty(window, "innerWidth", {
        configurable: true,
        value: originalWidth * 1.5,
      });
      window.dispatchEvent(new Event("resize"));
      check(
        "A visual-only resize leaves the newer reading scroll untouched",
        Math.abs(scrollY - before) < 1,
      );
      check(
        "A visual-only resize does not scale or narrow the reading column",
        article.getBoundingClientRect().width === beforeWidth &&
          getComputedStyle(article).fontSize === "13px",
      );
    } finally {
      if (descriptor) Object.defineProperty(window, "innerWidth", descriptor);
      else delete window.innerWidth;
      window.dispatchEvent(new Event("resize"));
    }
    document.querySelector("#reader-larger").click();
    check("A+ changes 13 to 14 without skipping sizes", size() === 14);
    document.querySelector("#reader-larger").click();
    await until(
      () =>
        target().dataset.mathState === "ready" && getComputedStyle(target()).fontSize === "15px",
      "chosen 15px font",
    );
    check(
      "Font changes preserve canonical mathematical content",
      logicalTextIndex(target()).text === canonical,
    );
    sessionStorage.setItem(testKey, JSON.stringify(report));
    document.body.dataset.viewportState = "await-reload";
    return;
  }
  check(
    "A new explicit font choice survives a reload",
    size() === 15 && getComputedStyle(article).fontSize === "15px",
  );
  while (size() > 13) document.querySelector("#reader-smaller").click();
  for (const width of [390, 320, 430, 390]) {
    document.body.dataset.viewportState = `await-${width}`;
    await until(() => innerWidth === width, `external width ${width}`);
    target().scrollIntoView({ block: "start" });
    await frame();
    await new Promise((resolve) => setTimeout(resolve, 200));
    await until(() => target().dataset.mathState === "ready", `math at ${width}`);
    const available = document.documentElement.clientWidth;
    check(
      `${width}px fills the layout width with no page overflow`,
      Math.abs(article.getBoundingClientRect().width - available) < 1 &&
        document.documentElement.scrollWidth <= available + 1,
    );
    check(
      `${width}px retains 13px math and its canonical text`,
      getComputedStyle(target()).fontSize === "13px" &&
        logicalTextIndex(target()).text === canonical,
    );
    check(
      `${width}px math has no hidden horizontal content`,
      Math.max(...Object.values(mathOverflow(target()))) <= 1,
    );
    check(
      `${width}px uses no page transform or CSS zoom`,
      [document.documentElement, document.body, article].every(
        (node) =>
          getComputedStyle(node).transform === "none" && Number(getComputedStyle(node).zoom) === 1,
      ),
    );
    measurement(`${width}px`);
    publish();
    // Let the external driver observe this step before accepting a repeated width.
    if (width !== 390 || report.measurements.length === 2) await frame();
  }
  sessionStorage.removeItem(testKey);
  document.body.dataset.viewportState = report.errors.length ? "error" : "ready";
  publish();
}
run().catch((error) => {
  report.errors.push(String(error));
  document.body.dataset.viewportState = "error";
  publish();
});
