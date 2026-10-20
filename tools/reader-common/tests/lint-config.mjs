import assert from "node:assert/strict";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { ESLint } from "eslint";

const cwd = fileURLToPath(new URL("../../../", import.meta.url));
const eslint = new ESLint({ cwd });

test("browser policy rejects Node globals and Node policy rejects browser globals", async () => {
  const [browser] = await eslint.lintText("process.exit(0); document.querySelector('main');", {
    filePath: "tools/reader-common/selection/submission.js",
  });
  assert.deepEqual(
    browser.messages.map((message) => message.message),
    ["'process' is not defined."],
  );
  const [node] = await eslint.lintText("document.querySelector('main'); process.exit(0);", {
    filePath: "tools/flow-reader/terminal/options.mjs",
  });
  assert.deepEqual(
    node.messages.map((message) => message.message),
    ["'document' is not defined."],
  );
});

test("browser evaluation hosts accept both runtimes but reject unknown names", async () => {
  const [result] = await eslint.lintText("process.exitCode = 0; document.title; missingReader();", {
    filePath: "tools/flow-reader/tests/selection-browser.mjs",
  });
  assert.deepEqual(
    result.messages.map((message) => message.message),
    ["'missingReader' is not defined."],
  );
});

test("reader TypeScript is parsed and unused values are checked", async () => {
  const [result] = await eslint.lintText("const unusedReader: number = 1;", {
    filePath: "tools/typst-dom/src/index.mts",
  });
  assert.deepEqual(
    result.messages.map((message) => message.ruleId),
    ["@typescript-eslint/no-unused-vars"],
  );
});

test("vendor and generated bundles are excluded", async () => {
  for (const path of [
    "tools/flow-reader/web/vendor/mathjax/tex-chtml.js",
    "tools/typst-dom/dist/esm/index.mjs",
    "tools/typst-preview-frontend/dist/index.js",
  ]) {
    assert.equal(await eslint.isPathIgnored(path), true, path);
  }
});
