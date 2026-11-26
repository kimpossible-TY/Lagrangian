import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../web/${path}`, import.meta.url), "utf8");

test("web viewer branding is consistent across entry points", async () => {
  const [index, manifestText, reader, home] = await Promise.all([
    read("index.html"), read("manifest.webmanifest"), read("reader.js"), read("home/home.js"),
  ]);
  const manifest = JSON.parse(manifestText);
  assert.match(index, /<title>Lagrangian Web Viewer<\/title>/);
  assert.equal(manifest.name, "Lagrangian Web Viewer");
  assert.equal(manifest.short_name, "Lagrangian");
  assert.ok(reader.includes('document.title = parsed.title ? `${parsed.title} · Lagrangian Web Viewer` : "Lagrangian Web Viewer"'));
  assert.ok(home.includes('kind === "html" ? "Lagrangian Web Viewer" : "Paged Reader"'));
  assert.ok(home.includes('ready: "웹 뷰어 준비됨"'));
});
