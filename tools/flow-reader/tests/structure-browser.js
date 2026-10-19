import { logicalTextIndex } from "/rendering/math/identity.js";
import { mathOverflow } from "/rendering/math/layout.js";

const report = { width: innerWidth, checks: [], errors: [], measurements: [] };
const output = document.createElement("pre");
output.id = "structure-report";
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
function visual(root, selector) {
  return [...root.querySelectorAll(selector)].filter((n) => !n.closest("mjx-assistive-mml"));
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
try {
  await until(() => document.querySelector("#energy-frame .flow-math-view"), "source content");
  const source = new DOMParser().parseFromString(
    await (await fetch("/document.html")).text(),
    "text/html",
  );
  for (const font of [18, 30]) {
    const changed = Number(document.querySelector("#reader-size").value) !== font;
    const previous = new Map(
      [...document.querySelectorAll(".flow-equation[id]")].map((n) => [
        n.id,
        n.querySelector(".flow-math-view")?.firstElementChild,
      ]),
    );
    while (Number(document.querySelector("#reader-size").value) !== font)
      document
        .querySelector(
          Number(document.querySelector("#reader-size").value) < font
            ? "#reader-larger"
            : "#reader-smaller",
        )
        .click();
    for (const id of [
      "energy-frame",
      "fraction-frame",
      "root-frame",
      "matrix-frame",
      "marked-frame",
      "product-frame",
      "bar-frame",
    ]) {
      if (!document.getElementById(id)) {
        location.hash = `#${id}`;
        await until(() => document.getElementById(id), `${id} transport section`);
      }
      const component = document.getElementById(id);
      const view = component.querySelector(".flow-math-view");
      component.scrollIntoView({ block: "start" });
      await until(
        () =>
          !["native", "pending"].includes(view.dataset.mathState) &&
          (!changed || !previous.get(id) || previous.get(id) !== view.firstElementChild),
        `${font}px ${id}`,
      );
      check(`${font}px ${id} fits without a layout notice`, view.dataset.mathState === "ready");
      const expected = logicalTextIndex(source.querySelector(`#${id} math`)).text;
      check(
        `${font}px ${id} retains canonical mathematical text`,
        logicalTextIndex(view).text === expected && copy(view) === expected,
      );
      const style = getComputedStyle(component);
      const rect = component.getBoundingClientRect();
      const width =
        component.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      const overflow = mathOverflow(view, {
        width,
        left: rect.left + parseFloat(style.paddingLeft),
      });
      check(
        `${font}px ${id} has no horizontal ink or scroll overflow`,
        Math.max(overflow.left, overflow.right) <= 1 &&
          component.scrollWidth <= component.clientWidth + 1,
      );
      const ink = visual(view, "mjx-c,mjx-utext,mjx-stretchy-h,mjx-stretchy-v")
        .filter(
          (n) =>
            !n.closest("mjx-stretchy-h,mjx-stretchy-v") ||
            n.matches("mjx-stretchy-h,mjx-stretchy-v"),
        )
        .flatMap((n) => [...n.getClientRects()]);
      check(
        `${font}px ${id} exposes all vertical content`,
        ink.every((r) => r.top >= rect.top - 1 && r.bottom <= rect.bottom + 1),
      );
      if (id === "matrix-frame") {
        const mml = view.querySelector("mjx-assistive-mml mtable");
        check(
          `${font}px the matrix retains four rows and four columns`,
          mml.children.length === 4 && [...mml.children].every((r) => r.children.length === 4),
        );
        const table = view.querySelector("mjx-mtable");
        check(
          `${font}px both matrix fences span the full table`,
          visual(view, "mjx-stretchy-v").length === 2 &&
            visual(view, "mjx-stretchy-v").every(
              (n) => n.getBoundingClientRect().height >= table.getBoundingClientRect().height - 2,
            ),
        );
        const control = visual(view, "mjx-mi").find((n) => !n.closest("mjx-mtable"));
        const normalSize = parseFloat(getComputedStyle(control).fontSize);
        check(
          `${font}px matrix entries keep the normal reading math size`,
          visual(view, "mjx-mtd mjx-mi").every(
            (n) => Math.abs(parseFloat(getComputedStyle(n).fontSize) - normalSize) < 0.01,
          ),
        );
      }
      if (id === "energy-frame") {
        const norms = visual(view, "mjx-mrow[data-flow-frame-atom]").filter(
          (n) => n.textContent.startsWith("‖") && n.textContent.endsWith("‖"),
        );
        check(
          `${font}px the short norms stay on one line`,
          norms.length === 2 && norms.every((n) => n.getBoundingClientRect().height < font * 2),
        );
      }
      if (id === "marked-frame") {
        await until(
          () =>
            visual(view, "[data-flow-decoration]").every(
              (n) => n.dataset.decorationState === "ready",
            ),
          "fragment paint",
        );
        check(
          `${font}px every marked fragment retains original paint`,
          visual(view, "[data-flow-decoration]").length > 1 &&
            visual(view, "[data-flow-decoration]").every((n) => n.dataset.flowAnchor),
        );
      }
      if (id === "bar-frame") {
        const overline = visual(view, "mjx-mover[data-flow-overline]")[0];
        check(
          `${font}px the overline spans its complete multi-line body`,
          overline.querySelector("mjx-stretchy-h").getBoundingClientRect().width >=
            overline.querySelector("mjx-base").getBoundingClientRect().width - 1,
        );
      }
      report.measurements.push({ font, id, width, height: rect.height, overflow });
    }
  }
  document.getElementById("energy-frame").scrollIntoView({ block: "start" });
  check(
    "The complete fixture needs no horizontal page movement",
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1,
  );
  document.body.dataset.structureState = report.errors.length ? "error" : "ready";
} catch (error) {
  report.errors.push(String(error));
  document.body.dataset.structureState = "error";
}
output.textContent = JSON.stringify(report, null, 2);
