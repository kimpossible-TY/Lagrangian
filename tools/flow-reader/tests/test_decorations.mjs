import assert from "node:assert/strict";
import test from "node:test";
import { MathDecorations } from "../web/decorations.js";

test("a split term retains every rectangle without painting the gap between lines", () => {
  const original = [globalThis.getComputedStyle, globalThis.innerHeight];
  globalThis.getComputedStyle = () => ({ fontSize: "18px", color: "rgb(36, 44, 52)" });
  globalThis.innerHeight = 844;
  const surface = {
    clientLeft: 0,
    clientTop: 0,
    scrollLeft: 0,
    scrollTop: 0,
    getBoundingClientRect: () => ({ left: 10, top: 20 }),
  };
  const rects = [
    { left: 20, top: 30, bottom: 50, width: 80, height: 20 },
    { left: 30, top: 60, bottom: 80, width: 40, height: 20 },
  ];
  const node = {
    closest: (selector) => (selector === ".flow-math-view" ? null : surface),
    getClientRects: () => rects,
  };
  const value = Object.create(MathDecorations.prototype);
  value.getRevision = () => "revision";
  try {
    const before = value.measure({ id: "d", nodes: [node] });
    assert.deepEqual(before.request.fragments, [
      { width: 80, height: 20 },
      { width: 40, height: 20 },
    ]);
    assert.equal(before.request.ink, "#242c34");
    rects[1].left += 5;
    const after = value.measure({ id: "d", nodes: [node] });
    assert.equal(before.signature, after.signature, "Unchanged fragment sizes can reuse paint");
    assert.notEqual(before.key, after.key, "Moved fragments must reposition that paint");
  } finally {
    [globalThis.getComputedStyle, globalThis.innerHeight] = original;
  }
});

test("temporary native math waits for composition before requesting decoration", () => {
  const value = Object.create(MathDecorations.prototype);
  for (const mathState of ["native", "pending"])
    assert.equal(value.measure({ nodes: [{ closest: () => ({ dataset: { mathState } }) }] }), null);
});

test("empty composed line-break carriers cannot retain a false loading notice", () => {
  const value = Object.create(MathDecorations.prototype);
  const surface = { isConnected: true };
  const notice = { textContent: "old loading message" };
  let mathState = "ready",
    width = 0;
  const node = {
    dataset: { decorationState: "pending" },
    closest: () => ({ dataset: { mathState } }),
    getClientRects: () => [{ width, height: 30 }],
  };
  Object.assign(value, {
    preserve: (change) => change(),
    surface: () => surface,
    notices: new Map([[surface, notice]]),
    records: new Map([["d", { nodes: [node] }]]),
  });
  value.status();
  assert.equal(notice.textContent, "", "No missing paint exists on the empty carrier");
  width = 20;
  value.status();
  assert.match(notice.textContent, /준비하는 중/, "Real unpainted content keeps its notice");
  width = 0;
  mathState = "native";
  value.status();
  assert.match(notice.textContent, /준비하는 중/, "Native placeholders still await composition");
});

test("a visible cancellation does not wait for its uncomposed explanatory copy", () => {
  const original = [globalThis.getComputedStyle, globalThis.innerHeight];
  globalThis.getComputedStyle = () => ({ fontSize: "13px", color: "rgb(36, 44, 52)" });
  globalThis.innerHeight = 844;
  const surface = {
    clientLeft: 0,
    clientTop: 0,
    scrollLeft: 0,
    scrollTop: 0,
    getBoundingClientRect: () => ({ left: 10, top: 20 }),
  };
  const states = ["ready", "native"];
  const nodes = states.map((_, member) => ({
    closest: (selector) =>
      selector === ".flow-math-view" ? { dataset: { mathState: states[member] } } : surface,
    getClientRects: () => [{ left: 20, top: 30, bottom: 50, width: 80, height: 20 }],
  }));
  const value = Object.create(MathDecorations.prototype);
  value.getRevision = () => "revision";
  try {
    const source = value.measure({ id: "cancellation", nodes });
    assert.equal(source.fragments.length, 1);
    assert.equal(source.fragments[0].node, nodes[0]);
    states.reverse();
    const copy = value.measure({ id: "cancellation", nodes });
    assert.equal(copy.fragments[0].node, nodes[1]);
    assert.equal(source.signature, copy.signature, "Equal geometry can reuse the callback paint");
    assert.notEqual(source.key, copy.key, "A different occurrence must receive its own paint");
    states[0] = "ready";
    assert.equal(value.measure({ id: "cancellation", nodes }).fragments.length, 2);
  } finally {
    [globalThis.getComputedStyle, globalThis.innerHeight] = original;
  }
});

test("previously composed offscreen copies cannot supply stale fragment geometry", () => {
  const original = [globalThis.getComputedStyle, globalThis.innerHeight];
  globalThis.getComputedStyle = () => ({ fontSize: "30px", color: "rgb(36, 44, 52)" });
  globalThis.innerHeight = 844;
  const surface = {
    clientLeft: 0,
    clientTop: 0,
    scrollLeft: 0,
    scrollTop: 0,
    getBoundingClientRect: () => ({ left: 0, top: 0 }),
  };
  const nodes = [30, 4400].map((top, member) => ({
    closest: (selector) =>
      selector === ".flow-math-view" ? { dataset: { mathState: "ready" } } : surface,
    getClientRects: () => [
      { left: 20, top, bottom: top + 20, width: member ? 80 : 40, height: 20 },
    ],
  }));
  const value = Object.create(MathDecorations.prototype);
  value.getRevision = () => "revision";
  try {
    const result = value.measure({ id: "d", nodes });
    assert.deepEqual(result.request.fragments, [{ width: 40, height: 20 }]);
    assert.equal(result.fragments[0].node, nodes[0]);
  } finally {
    [globalThis.getComputedStyle, globalThis.innerHeight] = original;
  }
});

test("a narrower or pending layout retires old paint before a busy compiler can finish", () => {
  const value = Object.create(MathDecorations.prototype);
  const record = {
    key: "wide",
    nodes: [{ dataset: { flowAnchor: "old" } }],
    svgs: [
      {
        remove() {
          this.removed = true;
        },
      },
    ],
  };
  const paint = record.svgs[0];
  Object.assign(value, {
    busy: true,
    records: new Map([["d", record]]),
    measure: () => ({ key: "narrow" }),
    changed: () => {
      value.changedPaint = true;
    },
  });
  try {
    value.schedule();
    assert.equal(paint.removed, true);
    assert.equal(record.nodes[0].dataset.flowAnchor, undefined);
    assert.equal(record.nodes[0].dataset.decorationState, "pending");
    assert.equal(value.changedPaint, true);
    record.key = "narrow";
    record.svgs = [
      {
        remove() {
          assert.fail("Unchanged paint removed");
        },
      },
    ];
    value.schedule();
    record.svgs = [paint];
    paint.removed = false;
    value.measure = () => null;
    value.schedule();
    assert.equal(paint.removed, true, "Pending mathematics cannot retain stale paint");
  } finally {
    clearTimeout(value.timer);
  }
});

test("decoration responses from an obsolete document cannot paint the new one", async () => {
  let complete;
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    new Promise((resolve) => {
      complete = resolve;
    });
  const value = Object.create(MathDecorations.prototype);
  let oldPaintRemoved = false;
  const record = {
    id: "d",
    nodes: [{ dataset: { flowAnchor: "old geometry" } }],
    svgs: [
      {
        remove: () => {
          oldPaintRemoved = true;
        },
      },
    ],
  };
  Object.assign(value, {
    sequence: 1,
    revision: "old",
    cache: new Map(),
    records: new Map([["d", record]]),
    getRevision: () => value.revision,
    measure: () => ({ request: {}, key: "position", signature: "geometry" }),
    status: () => {},
    changed: () => {},
    apply: () => assert.fail("Stale decoration painted"),
    schedule: () => {
      value.scheduled = true;
    },
  });
  try {
    const pending = value.render();
    assert.equal(oldPaintRemoved, true, "Old paint must not cover newly laid-out symbols");
    assert.equal(record.nodes[0].dataset.flowAnchor, undefined);
    value.sequence++;
    value.revision = "new";
    complete({ ok: true, json: async () => ({ revision: "old", decorations: { d: [] } }) });
    await pending;
    assert.equal(value.cache.size, 0);
    assert.equal(value.scheduled, true);
  } finally {
    globalThis.fetch = original;
  }
});
