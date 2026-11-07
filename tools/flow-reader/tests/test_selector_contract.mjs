import { readFile } from "node:fs/promises";
import { test } from "node:test";
import assert from "node:assert/strict";
import { checkShell } from "./selector-contract.mjs";

for (const [name, file] of Object.entries({ home: "../web/home/index.html", reader: "../web/index.html" })) {
  test(`${name} static shell contract`, async () => {
    const html = await readFile(new URL(file, import.meta.url), "utf8");
    checkShell(name, html);
    const hook = name === "home" ? 'id="document-list"' : 'id="reader-document"';
    assert.throws(() => checkShell(name, html.replace(hook, "")), /missing hooks/);
  });
}

test("rendered fixture selector contract", { skip: !process.env.FLOW_READER_PLAYWRIGHT_MODULE && "Set FLOW_READER_PLAYWRIGHT_MODULE to run browser fixture checks", timeout: 120000 }, async () => {
  const { execFile } = await import("node:child_process");
  const { promisify } = await import("node:util");
  await promisify(execFile)(process.execPath, [new URL("./ui-baseline.mjs", import.meta.url).pathname, "--contract-only"], { env: process.env });
});
