import assert from "node:assert/strict";
import test from "node:test";
import { BrowserCompilerClient } from "../web/compiler/client.js";

test("browser lifecycle and failures report bounded termination causes", async () => {
  const saved = Object.fromEntries(
    ["document", "window", "navigator", "fetch"].map((key) => [
      key,
      Object.getOwnPropertyDescriptor(globalThis, key),
    ]),
  );
  const sent = [];
  const events = { addEventListener() {}, removeEventListener() {} };
  Object.defineProperty(globalThis, "document", {
    configurable: true,
    value: { ...events, visibilityState: "visible" },
  });
  Object.defineProperty(globalThis, "window", { configurable: true, value: events });
  Object.defineProperty(globalThis, "navigator", { configurable: true, value: { onLine: true } });
  globalThis.fetch = async (_, options) => {
    sent.push(JSON.parse(options.body));
    return {};
  };
  try {
    for (const reason of [
      "page-hidden",
      "page-exit",
      "offline",
      "disabled",
      "disposed",
      "worker-error",
      "compile-error",
      "client-timeout",
      "transport-error",
    ]) {
      const client = new BrowserCompilerClient();
      client.enabled = true;
      const session = {
        token: "secret",
        controller: new AbortController(),
        worker: { terminate() {} },
      };
      client.session = session;
      if (reason === "page-hidden") {
        globalThis.document.visibilityState = "hidden";
        client.update();
        globalThis.document.visibilityState = "visible";
      } else if (reason === "offline") {
        navigator.onLine = false;
        client.update();
        navigator.onLine = true;
      } else if (reason === "disabled") client.setEnabled(false);
      else if (reason === "disposed") client.dispose();
      else if (reason === "page-exit") client.hide();
      else
        client.fail(
          session,
          Object.assign(
            new Error("private detail"),
            reason === "transport-error" ? {} : { termination: reason },
          ),
        );
      assert.equal(sent.at(-1).reason, reason);
      assert.deepEqual(Object.keys(sent.at(-1)).sort(), ["reason", "worker"]);
      assert.equal(client.session, null);
      client.dispose();
    }
  } finally {
    for (const [key, descriptor] of Object.entries(saved)) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else delete globalThis[key];
    }
  }
});

test("optional tab checkpoint distinguishes a fresh page and keeps no lease credentials", () => {
  const keys = ["window", "document", "sessionStorage"];
  const saved = keys.map((key) => Object.getOwnPropertyDescriptor(globalThis, key));
  const storage = new Map();
  const events = { addEventListener() {}, removeEventListener() {} };
  try {
    Object.defineProperty(globalThis, "window", { configurable: true, value: events });
    Object.defineProperty(globalThis, "document", { configurable: true, value: events });
    Object.defineProperty(globalThis, "sessionStorage", {
      configurable: true,
      value: {
        getItem: (key) => storage.get(key),
        setItem: (key, value) => storage.set(key, value),
      },
    });
    const first = new BrowserCompilerClient();
    first.remember({
      device: { id: "1234abcd" },
      token: "secret",
      progress: { phase: "evaluating", wasmMemoryBytes: 1048576 },
    });
    assert.equal(first.recoveryMode, "same-page");
    const resumed = new BrowserCompilerClient();
    assert.equal(resumed.recoveryMode, "page-restart");
    assert.equal(resumed.previous.reason, "unreported");
    assert.equal(resumed.previous.progress.phase, "evaluating");
    assert.ok(![...storage.values()].some((value) => value.includes("secret")));
    Object.defineProperty(globalThis, "sessionStorage", {
      configurable: true,
      get() {
        throw new Error("Storage unavailable");
      },
    });
    const noStorage = new BrowserCompilerClient();
    assert.equal(noStorage.previous, null);
    assert.doesNotThrow(() => noStorage.remember({ device: { id: "1234abcd" } }));
    noStorage.dispose();
    first.dispose();
    resumed.dispose();
  } finally {
    keys.forEach((key, i) =>
      saved[i] ? Object.defineProperty(globalThis, key, saved[i]) : delete globalThis[key],
    );
  }
});
