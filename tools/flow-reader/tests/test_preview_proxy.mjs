import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const script = readFileSync(new URL("../web/preview-proxy.js", import.meta.url), "utf8");

for (const origin of ["http://127.0.0.1:8769", "https://reader.example"]) {
  test(`preview bridge scopes root/theme/viewer sockets at ${origin}`, () => {
    const calls = [];
    class NativeSocket {
      static OPEN = 1;
      constructor(...args) {
        calls.push(args);
      }
    }
    const window = { WebSocket: NativeSocket };
    vm.runInNewContext(script, {
      window,
      document: {
        currentScript: {
          src: origin + "/p/alpha/__reader_preview_proxy__.js",
          dataset: { readerPreviewPort: "23625" },
        },
      },
      location: { href: origin + "/p/alpha/?page=2" },
      URL,
      DOMException,
    });
    const scheme = origin.startsWith("https") ? "wss" : "ws";
    const base = origin.replace(/^https?/, scheme) + "/p/alpha/";
    for (const [url, suffix] of [
      [origin + "/", ""],
      [origin + "/_theme/dark?revision=r1", "_theme/dark?revision=r1"],
      ["ws://127.0.0.1:23625/", ""],
      ["ws://localhost:23625/_theme/light", "_theme/light"],
      [origin + "/p/alpha/_theme/dark", "_theme/dark"],
      [origin + "/editor/channel?token=kept", "editor/channel?token=kept"],
      [origin + "/p/beta/", "p/beta/"],
    ]) {
      const socket = new window.WebSocket(url);
      assert.ok(socket instanceof NativeSocket);
      assert.equal(calls.at(-1)[0], base + suffix);
    }
    new window.WebSocket(origin + "/", ["preview"]);
    assert.deepEqual(Array.from(calls.at(-1)[1]), ["preview"]);
    assert.equal(window.WebSocket.OPEN, NativeSocket.OPEN);
    for (const url of [
      "ws://evil.example/",
      "ws://127.0.0.1:23626/",
      "ws://user:pass@127.0.0.1:23625/",
    ])
      assert.throws(() => new window.WebSocket(url), { name: "SecurityError" });
  });
}
