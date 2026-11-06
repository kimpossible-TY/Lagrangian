import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import test from "node:test";
import vm from "node:vm";

test("legacy worker retirement deletes only its own old scope caches", async () => {
  const script = execFileSync(
    "python3",
    [
      "-B",
      "-c",
      "from flow_reader.server.routing import RETIRE_WORKER; import sys; sys.stdout.buffer.write(RETIRE_WORKER)",
    ],
    { cwd: new URL("..", import.meta.url), encoding: "utf8" },
  );
  const scope = "http://127.0.0.1:23627/";
  const oldKeys = [`flow-offline-v1:${scope}:meta`, `flow-offline-v1:${scope}:snapshot-old`];
  const retained = [
    "flow-offline-v1:http://127.0.0.1:8769/d/first/:meta",
    "flow-offline-v1:http://127.0.0.1:23628/:meta",
    "unrelated-cache",
  ];
  const deleted = [],
    listeners = new Map();
  let skipped = false,
    unregistered = false,
    activation;
  vm.runInNewContext(script, {
    self: {
      addEventListener: (name, listener) => listeners.set(name, listener),
      skipWaiting: () => {
        skipped = true;
      },
      registration: {
        scope,
        unregister: async () => {
          unregistered = true;
        },
      },
    },
    caches: {
      keys: async () => [...oldKeys, ...retained],
      delete: async (key) => deleted.push(key),
    },
  });
  listeners.get("install")();
  listeners.get("activate")({
    waitUntil: (promise) => {
      activation = promise;
    },
  });
  await activation;
  assert.equal(skipped, true);
  assert.equal(unregistered, true);
  assert.deepEqual(deleted, oldKeys);
});
