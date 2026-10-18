import { logicalTextIndex } from "/math-identity.js";

const report = { checks: [], errors: [] };
const output = document.createElement("pre");
output.id = "paragraph-tabs-report";
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
function copy(node) {
  const range = document.createRange();
  range.selectNodeContents(node);
  const selection = getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
  const clipboardData = new DataTransfer();
  node.dispatchEvent(
    new ClipboardEvent("copy", { clipboardData, bubbles: true, cancelable: true }),
  );
  // Plain-text selections intentionally retain the browser's native copy path.
  const text = clipboardData.getData("text/plain") || selection.toString();
  selection.removeAllRanges();
  return text;
}

try {
  const article = document.querySelector("#reader-document");
  await until(() => article.querySelectorAll(".flow-paragraph-tab").length === 6, "paragraph tabs");
  const source = new DOMParser().parseFromString(
    await (await fetch("/document.html")).text(),
    "text/html",
  );
  const paragraphs = [...article.querySelectorAll("p")];
  const original = [...source.querySelectorAll("body p")].map(
    (node) => logicalTextIndex(node).text,
  );
  check(
    "Both aliases and highlighted/inline tabs are exported",
    paragraphs.length === 7 && Boolean(article.querySelector("mark .flow-paragraph-tab")),
  );
  for (const size of [13, 30]) {
    const control = document.querySelector("#reader-size");
    while (Number(control.value) !== size)
      document
        .querySelector(Number(control.value) < size ? "#reader-larger" : "#reader-smaller")
        .click();
    await until(
      () =>
        [...article.querySelectorAll(".flow-math-view")].every(
          (node) => node.dataset.mathState === "ready",
        ),
      `${size}px math`,
    );
    const tabs = [...article.querySelectorAll(".flow-paragraph-tab")];
    tabs.forEach((tab, index) => {
      check(
        `${size}px tab ${index}: inherited 1.5em spacing`,
        Math.abs(tab.getBoundingClientRect().width - 1.5 * size) < 0.1,
      );
      check(
        `${size}px tab ${index}: no quotation or assistive characters`,
        tab.textContent === "" && tab.getAttribute("aria-hidden") === "true",
      );
    });
    paragraphs.forEach((paragraph, index) => {
      check(
        `${size}px paragraph ${index}: canonical copy stays intact`,
        logicalTextIndex(paragraph).text === original[index] &&
          copy(paragraph).replace(/\s+/g, " ").trim() === original[index],
      );
    });
    const first = tabs[0].closest("p");
    const range = document.createRange();
    range.selectNodeContents(first.lastChild);
    const lines = [...range.getClientRects()].filter((rect) => rect.width > 1);
    check(
      `${size}px: only the first line is indented`,
      lines.length > 1 &&
        lines[0].left >= first.getBoundingClientRect().left + 1.5 * size - 1 &&
        Math.abs(lines[1].left - first.getBoundingClientRect().left) < 1,
    );
    check(
      `${size}px: ordinary paragraph keeps its original edge`,
      !paragraphs.at(-1).querySelector(".flow-paragraph-tab") &&
        Math.abs(
          paragraphs.at(-1).getBoundingClientRect().left - first.getBoundingClientRect().left,
        ) < 1,
    );
    check(
      `${size}px: no horizontal movement`,
      document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
    );
  }
  report.state = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(error.stack || String(error));
  report.state = "error";
}
output.textContent = JSON.stringify(report, null, 2);
