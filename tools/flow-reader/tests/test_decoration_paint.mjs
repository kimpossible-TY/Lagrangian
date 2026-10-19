import assert from "node:assert/strict";
import test from "node:test";
import { localDecorationPaint } from "../web/rendering/math/decoration-paint.js";
import { MathDecorations } from "../web/rendering/math/decorations.js";

const zero = { px: 0, em: 0 };
const edges = (value = zero) =>
  Object.fromEntries(["left", "right", "top", "bottom"].map((side) => [side, value]));
const spec = {
  version: 1,
  kind: "cancel",
  outset: edges(),
  inset: edges(),
  angle: null,
  ratio: 1,
  length: { px: 4, em: 0.3 },
  cross: false,
  inverted: false,
  stroke: { paint: "ink", thickness: { px: 0, em: 0.05 } },
};
const record = (id, paint = spec) => ({
  id,
  nodes: [{ dataset: paint ? { flowDecorationPaint: JSON.stringify(paint) } : {} }],
  svgs: [],
});
const request = {
  fontSize: 20,
  ink: "#123456",
  fragments: [
    { width: 80, height: 20 },
    { width: 40, height: 18 },
  ],
};

test("primitive validation falls back atomically for unsupported or inconsistent descriptions", () => {
  for (const paint of [
    null,
    { ...spec, version: 2 },
    { ...spec, kind: "callback" },
    { ...spec, angle: "eval()" },
    { ...spec, stroke: { ...spec.stroke, paint: "url(secret)" } },
    { ...spec, cross: "true" },
    { ...spec, outset: {} },
  ])
    assert.equal(localDecorationPaint(record("d", paint), request), null);
  const copy = record("d");
  copy.nodes.push({ dataset: {} });
  assert.equal(localDecorationPaint(copy, request), null);
  for (const fragments of [[{ width: NaN, height: 20 }], [{ width: -1, height: 20 }], []])
    assert.equal(localDecorationPaint(record("d"), { ...request, fragments }), null);
});

test("each fragment retains its own geometry, source ink, em scaling and anchor inset", () => {
  const paint = {
    ...spec,
    kind: "rect",
    fill: "#ffdc0066",
    outset: edges({ px: 2, em: 0.1 }),
    inset: edges({ px: 0, em: 0.025 }),
  };
  const drawings = localDecorationPaint(record("d", paint), request);
  assert.equal(drawings.length, 2);
  assert.deepEqual(drawings[0].layout, {
    left: -4,
    top: -4,
    width: 88,
    height: 28,
    anchor: { left: -4.5, top: -4.5, width: 89, height: 29 },
  });
  assert.equal(drawings[1].layout.width, 48);
  assert.match(drawings[0].svg, /fill="#ffdc0066" stroke="#123456" stroke-width="1"/);
  const large = localDecorationPaint(record("d", paint), { ...request, fontSize: 30 });
  assert.equal(large[0].layout.width, 90);
  assert.match(large[0].svg, /stroke-width="1.5"/);
});

test("mixed local and callback paint requests only callbacks and holds all work during gestures", async () => {
  const previous = globalThis.fetch;
  const local = record("local"),
    callback = record("callback", null);
  const painted = [],
    requests = [];
  const value = Object.create(MathDecorations.prototype);
  let held = true;
  Object.assign(value, {
    sequence: 1,
    records: new Map([
      [local.id, local],
      [callback.id, callback],
    ]),
    cache: new Map(),
    getRevision: () => "revision",
    selectionActive: () => held,
    measure: () => ({ request, key: "geometry", signature: "sizes" }),
    status: () => {},
    changed: () => {},
    apply: (record, drawings) => {
      record.key = "geometry";
      painted.push([record.id, drawings]);
    },
  });
  globalThis.fetch = async (_, options) => {
    requests.push(JSON.parse(options.body));
    return {
      ok: true,
      json: async () => ({ revision: "revision", decorations: { callback: [] } }),
    };
  };
  try {
    await value.render();
    assert.equal(requests.length, 0);
    assert.equal(painted.length, 0);
    held = false;
    await value.render();
    assert.deepEqual(
      painted.map(([id]) => id),
      ["local", "callback"],
    );
    assert.deepEqual(Object.keys(requests[0].decorations), ["callback"]);
    value.records.delete("callback");
    local.key = undefined;
    value.busy = true;
    await value.render();
    assert.equal(painted.at(-1)[0], "local", "Unrelated server work cannot delay local paint");
    assert.equal(requests.length, 1);
  } finally {
    globalThis.fetch = previous;
  }
});

test("a gesture beginning during a response holds publication and the next fallback batch", async () => {
  const previous = globalThis.fetch;
  const value = Object.create(MathDecorations.prototype);
  let held = false,
    calls = 0,
    scheduled = false;
  Object.assign(value, {
    sequence: 1,
    records: new Map(Array.from({ length: 33 }, (_, i) => [`d-${i}`, record(`d-${i}`, null)])),
    cache: new Map(),
    getRevision: () => "revision",
    selectionActive: () => held,
    measure: (record) => ({ request, key: "geometry", signature: record.id }),
    status: () => {},
    changed: () => {},
    apply: () => assert.fail("Held response painted"),
    schedule: () => {
      scheduled = true;
    },
  });
  globalThis.fetch = async (_, options) => {
    calls++;
    held = true;
    const ids = Object.keys(JSON.parse(options.body).decorations);
    return {
      ok: true,
      json: async () => ({
        revision: "revision",
        decorations: Object.fromEntries(ids.map((id) => [id, []])),
      }),
    };
  };
  try {
    await value.render();
    assert.equal(calls, 1, "Next batch waits for gesture release");
    assert.equal(value.cache.size, 32, "Completed paint can be reused after release");
    assert.equal(scheduled, true);
  } finally {
    globalThis.fetch = previous;
  }
});
