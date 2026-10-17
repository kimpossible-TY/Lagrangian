import assert from "node:assert/strict";
import test from "node:test";
import { GraphicalAnnotations } from "../web/graphics.js";

function renderer() {
  const record = {
    id: "graphic-1",
    note: { dataset: {} },
    scene: { visible: true, node: { isConnected: true } },
  };
  const value = Object.create(GraphicalAnnotations.prototype);
  Object.assign(value, {
    sequence: 1,
    revision: "old",
    records: new Map([[record.id, record]]),
    cache: new Map(),
    getRevision: () => value.revision,
    measure: () => ({ key: "old-position", signature: "request", geometry: {} }),
    apply: () => assert.fail("Obsolete geometry changed the body"),
    schedule: () => {
      value.scheduled = true;
    },
  });
  return { value, record };
}

test("an annotation response cannot enter a newer document", async () => {
  const { value } = renderer();
  let complete;
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    new Promise((resolve) => {
      complete = resolve;
    });
  try {
    const rendering = value.render();
    value.sequence++;
    value.revision = "new";
    complete({
      ok: true,
      json: async () => ({ revision: "old", graphics: { "graphic-1": "svg" } }),
    });
    await rendering;
    assert.equal(value.cache.size, 0);
    assert.equal(value.scheduled, true);
  } finally {
    globalThis.fetch = original;
  }
});

test("a changed term position rejects the old overlay and schedules a new measurement", async () => {
  const { value } = renderer();
  let complete;
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    new Promise((resolve) => {
      complete = resolve;
    });
  try {
    const rendering = value.render();
    value.measure = () => ({ key: "new-position" });
    complete({
      ok: true,
      json: async () => ({ revision: "old", graphics: { "graphic-1": "svg" } }),
    });
    await rendering;
    assert.equal(value.scheduled, true);
    assert.equal(value.cache.get("request"), "svg");
  } finally {
    globalThis.fetch = original;
  }
});

test("parking an older scene does not remove a replacement with the same annotation ID", () => {
  const { value, record } = renderer();
  const old = { id: record.id };
  const scene = { node: { isConnected: false }, body: {}, records: [old] };
  value.scenes = new Set([scene]);
  value.intersection = { unobserve: () => {} };
  value.resize = { unobserve: () => {} };
  value.sync();
  assert.equal(value.scenes.size, 0);
  assert.equal(value.records.get(record.id), record);
  assert.equal(value.scheduled, true);
});

test("a failed annotation request retries automatically without a reveal control", async () => {
  const { value, record } = renderer();
  const original = globalThis.fetch;
  globalThis.fetch = async () => ({ ok: false });
  try {
    await value.render();
    assert.equal(record.note.dataset.graphicState, "error");
    assert.match(record.note.textContent, /자동으로 다시 시도/);
    assert.ok(value.timer);
  } finally {
    clearTimeout(value.timer);
    globalThis.fetch = original;
  }
});
