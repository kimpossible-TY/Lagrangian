import { logicalTextIndex } from "/math-identity.js";

const report = { checks: [], errors: [] };
const output = document.createElement("pre");
output.id = "highlighted-report";
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
function paint(node) {
  return getComputedStyle(node).backgroundColor;
}
function copy(node) {
  const range = document.createRange();
  range.selectNodeContents(node);
  const selection = getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
  const clipboardData = new DataTransfer();
  node.dispatchEvent(
    new ClipboardEvent("copy", {
      clipboardData,
      bubbles: true,
      cancelable: true,
    }),
  );
  selection.removeAllRanges();
  return clipboardData.getData("text/plain");
}

try {
  const article = document.querySelector("#reader-document");
  await until(() => article.querySelector(".flow-highlight .flow-math-view"), "authored math");
  const views = [...article.querySelectorAll(".flow-highlight .flow-math-view")];
  const original = views.map((view) => logicalTextIndex(view).text);
  check("Every original mathematical expression stays inside its highlight", views.length === 5);
  check(
    "Plain text and strings retain their highlights",
    [...article.querySelectorAll("mark.flow-highlight")].filter(
      (mark) => !mark.querySelector(".flow-math-view") && mark.textContent.trim(),
    ).length === 5,
  );
  check(
    "Nested formatting and links retain their structure",
    Boolean(article.querySelector("mark strong .flow-math-view")) &&
      Boolean(article.querySelector('mark a[href="#target"]')),
  );

  for (const size of [13, 30]) {
    const control = document.querySelector("#reader-size");
    while (Number(control.value) !== size)
      document
        .querySelector(Number(control.value) < size ? "#reader-larger" : "#reader-smaller")
        .click();
    // Keep every fixture expression in the renderer's composition margin.
    views[2].scrollIntoView({ block: "center" });
    await until(
      () =>
        views.every((view) => view.dataset.mathState === "ready") &&
        Math.abs(parseFloat(getComputedStyle(views[0]).fontSize) - size) < 0.1,
      `${size}px composition`,
    );
    for (const theme of ["light", "dark", "light"]) {
      const themeControl = document.querySelector("#reader-theme");
      themeControl.value = theme;
      themeControl.dispatchEvent(new Event("change", { bubbles: true }));
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      const mark = article.querySelector("mark.flow-highlight");
      const expectedPaint = paint(mark);
      check(
        `${size}px ${theme}: text has a visible theme background`,
        expectedPaint !== "rgba(0, 0, 0, 0)" && expectedPaint !== "transparent",
      );
      views.forEach((view, index) => {
        check(
          `${size}px ${theme} expression ${index}: full mathematical background`,
          paint(view) === expectedPaint,
        );
        check(
          `${size}px ${theme} expression ${index}: original text and canonical copy`,
          logicalTextIndex(view).text === original[index] && copy(view) === original[index],
        );
        const bounds = view.getBoundingClientRect();
        const math = view.querySelector("mjx-container").getBoundingClientRect();
        check(
          `${size}px ${theme} expression ${index}: paint covers tall math`,
          bounds.top <= math.top + 1 && bounds.bottom >= math.bottom - 1,
        );
        check(
          `${size}px ${theme} expression ${index}: no horizontal scrolling`,
          view.scrollWidth <= view.clientWidth + 1,
        );
      });
      const ordinary = [...article.querySelectorAll(".flow-math-view")].find(
        (view) => !view.closest(".flow-highlight"),
      );
      check(
        `${size}px ${theme}: ordinary mathematics remains unhighlighted`,
        paint(ordinary) === "rgba(0, 0, 0, 0)" || paint(ordinary) === "transparent",
      );
    }
  }
  check(
    "The long inline expression reflows into the body",
    article.clientWidth > 400 || views[3].getBoundingClientRect().height > 60,
  );
  check(
    "The reading page needs no horizontal movement",
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  report.state = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(error.stack || String(error));
  report.state = "error";
}
output.textContent = JSON.stringify(report, null, 2);
