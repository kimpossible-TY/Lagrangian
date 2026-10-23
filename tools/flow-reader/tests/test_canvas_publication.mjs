import assert from "node:assert/strict";
import test from "node:test";
import { NativeCanvasLabels } from "../web/rendering/graphics/canvas-labels.js";
import { composeCanvas } from "../web/rendering/graphics/canvas-layout.js";

function fixture() {
  const jobs = [];
  const state = { held: false, changes: 0 };
  const empty = () => [];
  const canvas = Object.create(NativeCanvasLabels.prototype);
  Object.assign(canvas, {
    node: { dataset: {}, isConnected: true, querySelectorAll: empty },
    model: { width: 100, height: 80, labels: [] },
    labels: [],
    svg: { style: {}, querySelectorAll: empty, viewBox: { baseVal: { width: 100 } } },
    stage: { style: {}, getBoundingClientRect: () => ({ left: 0, top: 0 }) },
    overlay: { style: {}, replaceChildren() {}, setAttribute() {} },
    markers: { replaceChildren() {} },
    preserve: (action) => action(),
    selectionActive: () => state.held,
    changed: () => state.changes++,
    compute: (input) =>
      new Promise((resolve) =>
        jobs.push({ input, finish: () => resolve(composeCanvas(...input)) }),
      ),
  });
  return { canvas, state, jobs };
}

test("a stale Worker response cannot publish after width/font preparation", async () => {
  const { canvas, jobs } = fixture();
  assert.equal(canvas.layout(320, 18), false);
  const old = canvas.pending;
  canvas.prepare(768, 30);
  assert.equal(canvas.layout(768, 30), false);
  assert.equal(jobs.length, 1, "A figure has at most one outstanding computation");
  jobs[0].finish();
  await old;
  assert.equal(canvas.completed, null);
  assert.equal(canvas.node.dataset.canvasWidth, undefined);
  assert.equal(canvas.layout(768, 30), false);
  jobs[1].finish();
  await canvas.pending;
  assert.equal(canvas.layout(768, 30), true);
  assert.equal(canvas.node.dataset.canvasWidth, 768);
  assert.equal(canvas.node.dataset.canvasFont, 30);
});

test("a selection holds completed geometry until release, and disposal prevents publication", async () => {
  const { canvas, state, jobs } = fixture();
  canvas.layout(320, 18);
  state.held = true;
  jobs[0].finish();
  await canvas.pending;
  assert.equal(canvas.layout(320, 18), false);
  assert.equal(canvas.node.dataset.canvasWidth, undefined);
  state.held = false;
  assert.equal(canvas.layout(320, 18), true);
  assert.equal(canvas.node.dataset.canvasWidth, 320);
  canvas.layout(390, 20);
  const pending = canvas.pending;
  const changes = state.changes;
  canvas.dispose();
  jobs[1].finish();
  await pending;
  assert.equal(state.changes, changes);
  assert.equal(canvas.layout(390, 20), false);
  assert.equal(canvas.node.dataset.canvasWidth, 320);
});
