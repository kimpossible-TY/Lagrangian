import assert from "node:assert/strict";
import test from "node:test";
import { loadMathJax } from "../web/rendering/math/loader.js";

test("network and startup failures release the loader for an automatic retry", async () => {
  const previous = [globalThis.document, globalThis.MathJax];
  const scripts = [];
  globalThis.document = {
    createElement: () => ({
      remove() {
        this.removed = true;
      },
    }),
    head: { append: (script) => scripts.push(script) },
  };
  try {
    let pending = loadMathJax();
    assert.equal(loadMathJax(), pending, "Concurrent requests share the same loader");
    scripts.at(-1).onerror();
    await assert.rejects(pending, /불러오지 못했습니다/);
    assert.equal(scripts.at(-1).removed, true);

    pending = loadMathJax();
    scripts.at(-1).onload();
    await assert.rejects(pending, /시작하지 못했습니다/);
    assert.equal(scripts.at(-1).removed, true);

    pending = loadMathJax();
    globalThis.MathJax.startup.promise = Promise.reject(new Error("Startup failed"));
    scripts.at(-1).onload();
    await assert.rejects(pending, /Startup failed/);

    pending = loadMathJax();
    const mathjax = globalThis.MathJax;
    mathjax.startup.promise = Promise.resolve();
    scripts.at(-1).onload();
    assert.equal(await pending, mathjax);
    assert.equal(loadMathJax(), pending);
    assert.equal(scripts.length, 4);
  } finally {
    [globalThis.document, globalThis.MathJax] = previous;
  }
});
