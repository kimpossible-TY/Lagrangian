import { ResponsiveMath } from "/rendering/math/renderer.js";
import { logicalTextIndex } from "/rendering/math/identity.js";

const report = { checks: [], errors: [] };
const output = document.createElement("pre");
output.id = "equation-numbers-report";
output.style.cssText = "white-space:pre-wrap;font:13px/1.5 monospace;margin:16px";
document.body.append(output);
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  output.textContent = JSON.stringify(report, null, 2);
}

const host = document.createElement("div");
host.style.cssText = "position:fixed;top:0;left:-100000px;pointer-events:none";
host.inert = true;
host.setAttribute("aria-hidden", "true");
const renderer = new ResponsiveMath(host, {
  preserve: (change) => change(),
  changed() {},
  selectionActive: () => false,
});
try {
  const deadline = Date.now() + 30000;
  while (!document.querySelector("#reader-document .flow-equation")) {
    if (Date.now() > deadline) throw new Error("Timed out waiting for the document");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  const source = new DOMParser().parseFromString(
    await (await fetch("/document.html")).text(),
    "text/html",
  );
  const equations = [...source.querySelectorAll(".flow-equation")];
  for (const equation of equations) {
    const number = equation.querySelector(".flow-equation-number");
    if (number)
      check("Exported number shares the expression's parent", number.parentElement === equation);
    equation.removeAttribute("id");
  }
  const expected = equations.map((node) => logicalTextIndex(node.querySelector("math")).text);
  const numbers = equations.map((node) => node.querySelector(".flow-equation-number")?.textContent);
  host.append(...equations);
  const article = document.querySelector("#reader-document");
  host.style.width = `${article.clientWidth}px`;
  article.append(host);
  function geometry(label, composed) {
    equations.forEach((equation, index) => {
      const math = equation.querySelector(composed ? ".flow-math-view" : "math");
      const bounds = math.getBoundingClientRect();
      const number = equation.querySelector(".flow-equation-number");
      if (number) {
        const rect = number.getBoundingClientRect();
        check(
          `${label} equation ${index}: number vertically centered`,
          Math.abs((rect.top + rect.bottom - bounds.top - bounds.bottom) / 2) < 1,
        );
        check(`${label} equation ${index}: number has its own space`, bounds.right < rect.left);
        check(
          `${label} equation ${index}: number stays intact`,
          number.textContent === numbers[index],
        );
        check(
          `${label} equation ${index}: number at inline end`,
          Math.abs(
            rect.right -
              equation.getBoundingClientRect().right +
              parseFloat(getComputedStyle(equation).paddingRight),
          ) < 1,
        );
      } else {
        const style = getComputedStyle(equation);
        check(
          `${label} unnumbered equation uses full width`,
          Math.abs(
            bounds.width -
              equation.clientWidth +
              parseFloat(style.paddingLeft) +
              parseFloat(style.paddingRight),
          ) < 1,
        );
      }
      if (composed) {
        check(`${label} equation ${index}: composition ready`, math.dataset.mathState === "ready");
        check(
          `${label} equation ${index}: original text`,
          logicalTextIndex(math).text === expected[index],
        );
        check(
          `${label} equation ${index}: fits without scrolling`,
          math.scrollWidth <= math.clientWidth + 1,
        );
        check(
          `${label} equation ${index}: block fits`,
          equation.scrollWidth <= equation.clientWidth + 1,
        );
      }
    });
  }
  geometry("Native", false);
  renderer.prepare(host);
  for (const font of [13, 18, 30]) {
    host.style.fontSize = `${font}px`;
    await renderer.render();
    geometry(`${font}px`, true);
  }
  host.style.width = `${Math.max(160, article.clientWidth - 80)}px`;
  await renderer.render();
  geometry("Narrowed at 30px", true);
  host.style.width = `${article.clientWidth}px`;
  await renderer.render();
  geometry("Widened at 30px", true);
  const record = [...renderer.records][0];
  renderer.notice(record, "Test composition notice");
  const mathBounds = record.view.getBoundingClientRect();
  const numberBounds = record.view.parentElement
    .querySelector(".flow-equation-number")
    .getBoundingClientRect();
  check(
    "A notice stays below the expression and number",
    record.notice.getBoundingClientRect().top >= Math.max(mathBounds.bottom, numberBounds.bottom),
  );
  check(
    "A notice preserves the number's vertical center",
    Math.abs((numberBounds.top + numberBounds.bottom - mathBounds.top - mathBounds.bottom) / 2) < 1,
  );
  renderer.notice(record, null);
  check(
    "The original numbered reference remains available",
    Boolean(source.querySelector('a[href="#long"]')),
  );
  document.body.dataset.equationNumbersState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.equationNumbersState = "error";
} finally {
  renderer.clear();
  host.remove();
  output.textContent = JSON.stringify(report, null, 2);
}
