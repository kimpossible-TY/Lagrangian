import assert from "node:assert/strict";
import test from "node:test";
import { CanvasComputation } from "../web/rendering/graphics/canvas-computation.js";
import { composeCanvas } from "../web/rendering/graphics/canvas-layout.js";

const input = [
  { width: 100, height: 80 },
  320,
  [
    {
      id: "label",
      source: { left: 40, top: 30, width: 20, height: 10 },
      width: 60,
      height: 20,
      markerWidth: 24,
      markerHeight: 24,
    },
  ],
  18,
  [[{ x: 100, y: 100 }, { x: 200, y: 100 }, 1]],
];

function fixture(timeout = 10000) {
  const workers = [];
  const computation = new CanvasComputation(() => {
    const worker = {
      messages: [],
      postMessage(value) {
        this.messages.push(structuredClone(value));
      },
      terminate() {
        this.terminated = true;
      },
      finish(message = this.messages.at(-1)) {
        this.onmessage({ data: { id: message.id, plan: composeCanvas(...message.input) } });
      },
    };
    workers.push(worker);
    return worker;
  }, timeout);
  return { computation, workers };
}

test("placement messages correlate out-of-order results and preserve exact fallback output", async () => {
  const { computation, workers } = fixture();
  const secondInput = [input[0], 768, input[2], 30, input[4]];
  const first = computation.run(input),
    second = computation.run(secondInput);
  const worker = workers[0];
  worker.finish(worker.messages[1]);
  worker.finish(worker.messages[0]);
  assert.deepEqual(await first, composeCanvas(...input));
  assert.deepEqual(await second, composeCanvas(...secondInput));
  assert.equal(computation.pending.size, 0);
  computation.dispose();
  assert.equal(worker.terminated, true);
});

test("document replacement cancels old work, ignores late results and starts a fresh worker", async () => {
  const { computation, workers } = fixture();
  const first = computation.run(input);
  const rejected = assert.rejects(first, { name: "AbortError" });
  computation.reset();
  await rejected;
  const second = computation.run(input);
  workers[0].finish();
  assert.equal(computation.pending.size, 1);
  workers[1].finish();
  assert.deepEqual(await second, composeCanvas(...input));
  computation.dispose();
  await assert.rejects(computation.run(input), { name: "AbortError" });
});

test("unsupported workers, failed messages and timeouts retain the same local placement", async () => {
  const unsupported = new CanvasComputation(() => {
    throw new Error("Unavailable");
  });
  assert.deepEqual(await unsupported.run(input), composeCanvas(...input));
  unsupported.dispose();
  for (const kind of ["error", "messageerror", "timeout"]) {
    const { computation, workers } = fixture(10);
    const result = computation.run(input);
    if (kind !== "timeout") workers[0][`on${kind}`]();
    assert.deepEqual(await result, composeCanvas(...input));
    assert.equal(workers[0].terminated, true);
    assert.deepEqual(await computation.run(input), composeCanvas(...input));
    computation.dispose();
  }
});

test("bounded pending work falls back locally without filling the Worker queue", async () => {
  const { computation, workers } = fixture();
  const pending = Array.from({ length: 64 }, () => computation.run(input));
  assert.deepEqual(await computation.run(input), composeCanvas(...input));
  assert.equal(workers[0].messages.length, 64);
  const canceled = pending.map((job) => assert.rejects(job, { name: "AbortError" }));
  computation.dispose();
  await Promise.all(canceled);
});
