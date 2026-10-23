import assert from "node:assert/strict";
import test from "node:test";
import { ReaderRecovery, sameSnapshot, sameSession } from "../web/features/session/recovery.js";
import { ReaderTransport } from "../web/features/session/transport.js";

function harness(refresh) {
  const window = new EventTarget();
  const document = Object.assign(new EventTarget(), { hidden: false });
  const navigator = { onLine: true };
  const scheduled = new Map();
  let next = 0;
  let disconnected = 0;
  const recovery = new ReaderRecovery({
    refresh,
    window,
    document,
    navigator,
    disconnected: () => disconnected++,
    schedule: (action, delay) => {
      const id = ++next;
      scheduled.set(id, { action, delay });
      return id;
    },
    cancel: (id) => scheduled.delete(id),
  });
  return {
    recovery,
    window,
    document,
    navigator,
    scheduled,
    disconnected: () => disconnected,
    tick() {
      const [id, value] = scheduled.entries().next().value;
      scheduled.delete(id);
      return value.action();
    },
    delay: () => [...scheduled.values()][0]?.delay,
  };
}

test("polling backs off failures, coalesces requests and resets on recovery", async () => {
  let failed = true;
  let requests = 0;
  const h = harness(async () => {
    requests++;
    if (failed) throw Error("offline");
  });
  h.recovery.request();
  h.recovery.request();
  assert.equal(h.scheduled.size, 1);
  await h.tick();
  assert.equal(h.delay(), 6000);
  await h.tick();
  assert.equal(h.delay(), 12000);
  await h.tick();
  await h.tick();
  assert.equal(h.delay(), 30000);
  failed = false;
  h.window.dispatchEvent(new Event("online"));
  assert.equal(h.delay(), 0);
  await h.tick();
  assert.equal(h.delay(), 3000);
  assert.equal(requests, 5);
  h.recovery.dispose();
  assert.equal(h.scheduled.size, 0);
});

test("wake abandons a hung request and late callbacks cannot publish or schedule", async () => {
  const pending = [];
  let published = 0;
  const h = harness(async (signal, current) => {
    await new Promise((resolve) => pending.push({ signal, resolve }));
    if (current()) published++;
  });
  h.recovery.request();
  const first = h.tick();
  h.window.dispatchEvent(new Event("pageshow"));
  assert.equal(pending[0].signal.aborted, true);
  const second = h.tick();
  pending[0].resolve();
  await first;
  assert.equal(published, 0);
  assert.equal(h.scheduled.size, 0);
  pending[1].resolve();
  await second;
  assert.equal(published, 1);
  assert.equal(h.scheduled.size, 1);
  h.recovery.dispose();
});

test("hidden, offline and bfcache lifetimes suspend work until visible online resume", async () => {
  let calls = 0;
  const h = harness(async () => calls++);
  h.recovery.request();
  await h.tick();
  h.document.hidden = true;
  h.document.dispatchEvent(new Event("visibilitychange"));
  h.recovery.request();
  assert.equal(h.scheduled.size, 0);
  h.document.hidden = false;
  h.document.dispatchEvent(new Event("visibilitychange"));
  assert.equal(h.delay(), 0);
  await h.tick();
  h.navigator.onLine = false;
  h.window.dispatchEvent(new Event("offline"));
  assert.equal(h.scheduled.size, 0);
  assert.equal(h.disconnected(), 1);
  h.navigator.onLine = true;
  h.window.dispatchEvent(new Event("online"));
  await h.tick();
  h.window.dispatchEvent(new Event("pagehide"));
  h.recovery.request();
  assert.equal(h.scheduled.size, 0);
  h.window.dispatchEvent(new Event("pageshow"));
  await h.tick();
  assert.equal(calls, 4);
  h.recovery.dispose();
  for (const event of ["online", "offline", "pageshow"]) h.window.dispatchEvent(new Event(event));
  assert.equal(h.scheduled.size, 0);
  assert.equal(h.disconnected(), 1);
});

test("document identity and service epoch remain distinct from accepted content revision", () => {
  const left = { documentID: "book", revision: "hash", service: { pid: 3, startedAt: 4 } };
  const restarted = { ...left, service: { pid: 3, startedAt: 5 } };
  assert.equal(sameSnapshot(left, restarted), true);
  assert.equal(sameSession(left, restarted), false);
  assert.equal(sameSnapshot(left, { ...left, documentID: "other" }), false);
  assert.equal(sameSession(left, { ...left, revision: "other" }), false);
  assert.equal(sameSession(left, structuredClone(left)), true);
  assert.equal(sameSnapshot(null, null), false);
});

test("GET timeout and external cancellation bound both response and body reads", async () => {
  const transport = new ReaderTransport(async (_path, { signal }) => ({
    ok: true,
    json: () =>
      new Promise((resolve, reject) => {
        signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), {
          once: true,
        });
      }),
  }));
  await assert.rejects(transport.get("api/state", { timeout: 5 }), { name: "AbortError" });
  assert.equal(transport.pending.size, 0);
  const controller = new AbortController();
  const request = transport.get("api/state", { signal: controller.signal });
  await Promise.resolve();
  controller.abort();
  await assert.rejects(request, { name: "AbortError" });
  assert.equal(transport.pending.size, 0);
});

test("transport disposal prevents an already-returning body from becoming current", async () => {
  let finish;
  const transport = new ReaderTransport(async () => ({
    ok: true,
    text: () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
  }));
  const request = transport.get("api/sections/first", { format: "text" });
  await Promise.resolve();
  transport.dispose();
  finish("<p>obsolete</p>");
  await assert.rejects(request, { name: "AbortError" });
});
