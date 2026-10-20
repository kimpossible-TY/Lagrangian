// Real compiler and Reader shell; FLOW_READER_PACKAGES and Playwright required.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { createInterface } from "node:readline";

const playwright = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
assert.ok(process.env.FLOW_READER_PACKAGES, "Set FLOW_READER_PACKAGES");
const output = await mkdtemp(`${tmpdir()}/flowbox-browser-`);
const service = spawn(
  process.env.PYTHON || "python3",
  [
    new URL("../serve.py", import.meta.url).pathname,
    "--root",
    new URL("fixtures/", import.meta.url).pathname,
    "--entry",
    "flowbox.typ",
    "--package-path",
    process.env.FLOW_READER_PACKAGES,
    "--output",
    output,
    "--original-url",
    "https://example.invalid/paged",
    ...(process.env.FLOW_READER_TYPST ? ["--compiler", process.env.FLOW_READER_TYPST] : []),
  ],
  { stdio: ["ignore", "pipe", "pipe"] },
);
let log = "";
service.stderr.on("data", (data) => (log += data));
const lines = createInterface({ input: service.stdout });
try {
  const { url } = await new Promise((resolve, reject) => {
    lines.once("line", (line) => resolve(JSON.parse(line)));
    service.once("exit", (code) => reject(new Error(`Reader exited ${code}: ${log}`)));
  });
  for (const engine of ["chromium", "webkit"]) {
    const browser = await playwright[engine].launch({
      headless: true,
      ...(engine === "chromium" ? { channel: "chrome" } : {}),
    });
    try {
      const page = await browser.newPage({ viewport: { width: 390, height: 1200 } });
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(url);
      await page.waitForFunction(() => document.querySelectorAll(".flow-flowbox").length === 2);
      const canonical = await page.evaluate(async () => {
        const { logicalTextIndex } = await import("/rendering/math/identity.js");
        const source = new DOMParser().parseFromString(
          await (await fetch("/document.html")).text(),
          "text/html",
        );
        return [...source.querySelectorAll(".flow-flowbox")].map(
          (box) => logicalTextIndex(box, { includeNested: true }).text,
        );
      });
      let scenarios = 0;
      for (const width of [320, 390, 430, 768]) {
        await page.setViewportSize({ width, height: 1200 });
        for (const font of [13, 18, 30]) {
          await page.evaluate((font) => {
            while (Number(document.querySelector("#reader-size").value) !== font)
              document
                .querySelector(
                  Number(document.querySelector("#reader-size").value) < font
                    ? "#reader-larger"
                    : "#reader-smaller",
                )
                .click();
          }, font);
          for (const colorScheme of ["light", "dark"]) {
            await page.emulateMedia({ colorScheme });
            await page.waitForTimeout(300);
            await page.waitForFunction(() => {
              const views = [...document.querySelectorAll(".flow-flowbox .flow-math-view")];
              const marks = [
                ...document.querySelectorAll(".flow-flowbox [data-flow-decoration]"),
              ].filter(
                (node) =>
                  !node.closest("mjx-assistive-mml,.flow-math-stage") &&
                  node.getBoundingClientRect().width,
              );
              return (
                views.length >= 6 &&
                views.every((node) => node.dataset.mathState === "ready") &&
                marks.length >= 2 &&
                marks.every((node) => node.dataset.decorationState === "ready")
              );
            });
            const result = await page.evaluate(async () => {
              const { logicalTextIndex } = await import("/rendering/math/identity.js");
              const { mathOverflow } = await import("/rendering/math/layout.js");
              const boxes = [...document.querySelectorAll(".flow-flowbox")];
              const failures = [];
              let arrows = 0;
              const check = (name, value) => {
                if (!value) failures.push(name);
              };
              for (const box of boxes) {
                const style = getComputedStyle(box);
                check(
                  "complete frame",
                  ["Top", "Bottom", "Left", "Right"].every(
                    (side) => parseFloat(style[`border${side}Width`]) === 1,
                  ),
                );
                check("centered content", style.textAlign === "center");
                check("bounded box", box.scrollWidth <= box.clientWidth + 1);
                for (const math of box.querySelectorAll(
                  '.flow-math-view mjx-container[display="true"]',
                )) {
                  check(
                    "compact mathematical rows",
                    parseFloat(getComputedStyle(math).marginTop) <=
                      parseFloat(style.fontSize) * 0.16,
                  );
                }
                check(
                  "no extra rules",
                  !box.querySelector("hr") &&
                    ![box.previousElementSibling, box.nextElementSibling].some(
                      (node) => node?.tagName === "HR",
                    ),
                );
                for (const group of box.querySelectorAll(".flow-derivation")) {
                  const css = getComputedStyle(group);
                  check(
                    "unframed math rows",
                    parseFloat(css.borderTopWidth) === 0 && parseFloat(css.borderBottomWidth) === 0,
                  );
                }
                for (const equation of box.querySelectorAll(".flow-equation")) {
                  const view = equation.querySelector(".flow-math-view");
                  const number = equation.querySelector(".flow-equation-number");
                  const m = view.getBoundingClientRect(),
                    n = number.getBoundingClientRect();
                  check("centered number", Math.abs((m.top + m.bottom - n.top - n.bottom) / 2) < 1);
                  check("separate number column", m.right < n.left);
                  const overflow = mathOverflow(view);
                  check("readable math fits", overflow.left <= 1 && overflow.right <= 1);
                }
                for (const paragraph of [...box.children].filter((node) => node.tagName === "P")) {
                  check(
                    "compact paragraph gap",
                    parseFloat(getComputedStyle(paragraph).marginTop) <=
                      parseFloat(style.fontSize) * 0.61,
                  );
                  if (logicalTextIndex(paragraph).text === "↓") {
                    arrows++;
                    const arrow = paragraph.querySelector("mjx-container").getBoundingClientRect();
                    const bounds = paragraph.getBoundingClientRect();
                    check(
                      "centered arrow",
                      Math.abs((arrow.left + arrow.right - bounds.left - bounds.right) / 2) < 1,
                    );
                  }
                }
              }
              check("both authored arrows checked", arrows === 2);
              const marks = [...boxes[1].querySelectorAll("[data-flow-decoration]")].filter(
                (node) =>
                  !node.closest("mjx-assistive-mml,.flow-math-stage") &&
                  node.getBoundingClientRect().width,
              );
              check(
                "cancellation paint",
                marks.length >= 2 &&
                  marks.every((node) => node.dataset.decorationState === "ready"),
              );
              const reference = boxes[1].querySelector("a[href]");
              check(
                "resolved reference",
                Boolean(document.getElementById(reference.hash.slice(1))),
              );
              return {
                failures,
                text: boxes.map((box) => logicalTextIndex(box, { includeNested: true }).text),
              };
            });
            const label = `${engine}/${width}px/${font}px/${colorScheme}`;
            assert.deepEqual(result.failures, [], label);
            assert.deepEqual(result.text, canonical, `${label}: canonical text`);
            scenarios++;
            if (process.env.FLOW_READER_SCREENSHOTS && width === 390 && font === 18) {
              await mkdir(process.env.FLOW_READER_SCREENSHOTS, { recursive: true });
              await page.screenshot({
                path: `${process.env.FLOW_READER_SCREENSHOTS}/${engine}-${colorScheme}.png`,
                fullPage: true,
              });
            }
          }
        }
      }
      assert.deepEqual(errors, []);
      console.log(`PASS ${engine}: ${scenarios} flowbox width/font/theme scenarios`);
    } finally {
      await browser.close();
    }
  }
} finally {
  lines.close();
  service.kill("SIGTERM");
  if (service.exitCode === null) await once(service, "exit");
  await rm(output, { recursive: true, force: true });
}
