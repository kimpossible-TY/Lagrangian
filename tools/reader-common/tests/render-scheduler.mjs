import assert from "node:assert/strict";
import test from "node:test";
import { RenderScheduler } from "../rendering/scheduler.js";

function browser(t) {
  let next = 0;
  const frames = new Map();
  const timers = new Map();
  t.mock.method(globalThis, "setTimeout", (callback, delay) => {
    timers.set(++next, { callback, delay });
    return next;
  });
  t.mock.method(globalThis, "clearTimeout", (id) => timers.delete(id));
  const original = [globalThis.requestAnimationFrame, globalThis.cancelAnimationFrame];
  globalThis.requestAnimationFrame = (callback) => {
    frames.set(++next, callback);
    return next;
  };
  globalThis.cancelAnimationFrame = (id) => frames.delete(id);
  t.after(() => {
    [globalThis.requestAnimationFrame, globalThis.cancelAnimationFrame] = original;
  });
  return {
    frames,
    timers,
    frame() {
      const [id, callback] = frames.entries().next().value;
      frames.delete(id);
      return callback();
    },
    timer() {
      const [id, { callback }] = timers.entries().next().value;
      timers.delete(id);
      callback();
    },
  };
}

test("browser requests coalesce into one frame and completion may enqueue another", async (t) => {
  const clock = browser(t);
  let calls = 0;
  let completed = 0;
  const work = new RenderScheduler({
    render: () => calls++,
    onIdle() {
      assert.equal(work.active, false);
      if (++completed === 1) work.request();
    },
  });
  work.request();
  work.request();
  assert.equal(clock.frames.size, 1);
  await clock.frame();
  assert.equal(calls, 1);
  assert.equal(clock.frames.size, 1);
  await clock.frame();
  assert.equal(calls, 2);
  assert.equal(completed, 2);
  assert.equal(work.active, false);
});

test("asynchronous renders serialize and new requests wait for the running render", async (t) => {
  const clock = browser(t);
  let finish;
  let calls = 0;
  let completed = 0;
  const work = new RenderScheduler({
    render: () => (++calls === 1 ? new Promise((resolve) => (finish = resolve)) : undefined),
    onIdle: () => completed++,
  });
  work.request();
  const running = clock.frame();
  work.request();
  work.request();
  assert.equal(clock.frames.size, 0);
  assert.equal(calls, 1);
  finish();
  await running;
  assert.equal(completed, 0);
  assert.equal(clock.frames.size, 1);
  await clock.frame();
  assert.equal(calls, 2);
  assert.equal(completed, 1);
});

test("held work stays pending without polling or completion until the adapter resumes it", async (t) => {
  const clock = browser(t);
  let held = true;
  let calls = 0;
  let holds = 0;
  let completed = 0;
  const work = new RenderScheduler({
    render: () => calls++,
    blocked: () => held,
    onBlocked: () => holds++,
    onIdle: () => completed++,
  });
  work.request();
  await clock.frame();
  assert.equal(holds, 1);
  assert.equal(calls, 0);
  assert.equal(completed, 0);
  assert.equal(clock.frames.size + clock.timers.size, 0);
  held = false;
  work.request();
  await clock.frame();
  assert.equal(calls, 1);
  assert.equal(completed, 1);
});

test("debounce keeps the latest request and cancellation rejects already dispatched callbacks", async (t) => {
  const clock = browser(t);
  let calls = 0;
  const work = new RenderScheduler({ render: () => calls++ });
  work.request(100);
  work.request(200);
  assert.equal(clock.timers.size, 1);
  assert.equal([...clock.timers.values()][0].delay, 200);
  clock.timer();
  const obsolete = [...clock.frames.values()][0];
  work.cancel();
  work.request();
  await obsolete();
  assert.equal(calls, 0);
  assert.equal(clock.frames.size, 1);
  await clock.frame();
  assert.equal(calls, 1);
});

test("cancelled in-flight work cannot complete a new document or start concurrent work", async (t) => {
  const clock = browser(t);
  let finish;
  let calls = 0;
  let completed = 0;
  const work = new RenderScheduler({
    render: () => (++calls === 1 ? new Promise((resolve) => (finish = resolve)) : undefined),
    onIdle: () => completed++,
  });
  work.request();
  const running = clock.frame();
  work.cancel();
  work.request();
  assert.equal(clock.frames.size, 0);
  finish();
  await running;
  assert.equal(completed, 0);
  await clock.frame();
  assert.equal(calls, 2);
  assert.equal(completed, 1);
});

test("render failures report errors without completion and allow a later retry", async (t) => {
  const clock = browser(t);
  const failure = new Error("render failed");
  let fail = true;
  const errors = [];
  let completed = 0;
  const work = new RenderScheduler({
    render() {
      if (fail) throw failure;
    },
    onError: (error) => errors.push(error),
    onIdle: () => completed++,
  });
  work.request();
  await clock.frame();
  assert.deepEqual(errors, [failure]);
  assert.equal(completed, 0);
  fail = false;
  work.request();
  await clock.frame();
  assert.equal(completed, 1);
});

test("disposal cancels debounce and suppresses completion of in-flight rendering", async (t) => {
  const clock = browser(t);
  let finish;
  let completed = 0;
  const work = new RenderScheduler({
    render: () => new Promise((resolve) => (finish = resolve)),
    onIdle: () => completed++,
  });
  work.request();
  const running = clock.frame();
  work.dispose();
  work.request();
  finish();
  await running;
  assert.equal(completed, 0);
  assert.equal(work.active, false);
  assert.equal(clock.frames.size + clock.timers.size, 0);
  const delayed = new RenderScheduler({ render: () => assert.fail("disposed render") });
  delayed.request(100);
  delayed.dispose();
  assert.equal(clock.timers.size, 0);
});
