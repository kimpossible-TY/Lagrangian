import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const web = fileURLToPath(new URL("../web/", import.meta.url));
const routes = JSON.parse(readFileSync(path.join(web, "home-assets.json"), "utf8"));

test("Homepage component imports resolve through the explicit local manifest", () => {
  const roots = [
    "vendor/webawesome-3.14.0/components/dropdown/dropdown.js",
    "vendor/webawesome-3.14.0/components/dropdown-item/dropdown-item.js",
  ];
  const seen = new Set();
  while (roots.length) {
    const route = roots.pop();
    if (seen.has(route)) continue;
    seen.add(route);
    assert.equal(routes[route], route, route);
    const source = readFileSync(path.join(web, route), "utf8");
    for (const match of source.matchAll(/(?:from\s*|import\s*)["']([^"']+)["']/g)) {
      assert.ok(match[1].startsWith("."), `Non-local import in ${route}: ${match[1]}`);
      roots.push(path.posix.normalize(path.posix.join(path.posix.dirname(route), match[1])));
    }
    assert.doesNotMatch(source, /\bimport\s*\(/, `Dynamic import in ${route}`);
  }
  const styles = ["vendor/webawesome-3.14.0/styles/themes/default.css"];
  while (styles.length) {
    const route = styles.pop();
    assert.equal(routes[route], route, route);
    const source = readFileSync(path.join(web, route), "utf8");
    for (const match of source.matchAll(/@import\s+url\(["']?([^"')]+)["']?\)/g)) {
      assert.ok(!/^(?:[a-z]+:|\/\/|\/)/i.test(match[1]), `Non-local CSS import in ${route}`);
      styles.push(path.posix.normalize(path.posix.join(path.posix.dirname(route), match[1])));
    }
    assert.doesNotMatch(source, /url\(["']?https?:/i);
  }
  const css = "vendor/basecoat-1.1.0/basecoat.cdn.min.css";
  assert.equal(routes[css], css);
  assert.doesNotMatch(readFileSync(path.join(web, css), "utf8"), /@import\s|url\(["']?https?:/i);
});
