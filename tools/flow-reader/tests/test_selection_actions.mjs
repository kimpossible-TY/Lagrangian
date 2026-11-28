import assert from "node:assert/strict";
import test from "node:test";
import { SourceHighlightController } from "../web/features/source-highlight/controller.js";
import { ReaderSelectionActions } from "../web/features/selection/controller.js";
import { OptimisticHighlights } from "../../reader-common/source-highlight/optimistic.js";

function harness(editorServer, editorAttachment) {
  const selected = [{ key: "body", exact: "Selected", revision: "r1", service: { pid: 7 } }];
  const state = {
    document: { revision: "r1" },
    selection: selected,
    retained: null,
    messages: [],
    changes: 0,
    paint: [],
    released: false,
  };
  let resolve;
  let reject;
  const requests = [];
  let controller;
  const view = {
    document: () => state.document,
    editorServer: () => editorServer,
    editorAttachment: () => editorAttachment,
    selection: () => state.selection,
    sameSelection: (left, right) => JSON.stringify(left) === JSON.stringify(right),
    enabled: () => !controller.pending,
    collapse: () => {
      controller.dismiss();
      state.selection = null;
      state.retained = null;
    },
    releaseSelection: () => {
      state.released = true;
    },
    retain: (selection) => {
      state.selection = state.retained = selection;
    },
    announce: (text) => state.messages.push(text),
    changed: () => {
      state.changes++;
    },
  };
  const transport = {
    post: (...args) => {
      requests.push(args);
      return new Promise((done, failed) => {
        resolve = done;
        reject = failed;
      });
    },
  };
  const highlights = new OptimisticHighlights((selected) => (state.paint = selected));
  controller = new SourceHighlightController(view, transport, highlights);
  return {
    state,
    selected,
    requests,
    controller,
    highlights,
    resolve: (result) => resolve(result),
    reject: () => reject(new Error("offline")),
  };
}

test("highlight acknowledgment preserves a newer selection or revision", async () => {
  const h = harness();
  const pending = h.controller.submit(h.selected);
  assert.equal(h.controller.pending, true);
  await h.controller.submit(h.selected);
  assert.equal(h.requests.length, 1);
  assert.equal(h.requests[0][0], "api/highlight");
  const newer = [{ ...h.selected[0], exact: "New selection" }];
  h.state.selection = newer;
  h.resolve({ status: "highlighted" });
  await pending;
  assert.equal(h.state.selection, newer);
  assert.equal(h.controller.pending, false);
  const again = h.controller.submit(newer);
  h.state.document = { revision: "r2" };
  h.reject();
  await again;
  assert.equal(h.state.retained, null);
});

test("highlight failed submission retains a native collapsed range but respects dismissal", async () => {
  const h = harness();
  const pending = h.controller.submit(h.selected);
  h.state.selection = null;
  h.reject();
  await pending;
  assert.equal(h.state.retained, h.selected);
  const retry = h.controller.submit(h.selected);
  h.controller.dismiss();
  h.state.selection = null;
  h.state.retained = null;
  h.reject();
  await retry;
  assert.equal(h.state.retained, null);
});

test("source highlighting rejects a stale captured revision before writing", async () => {
  const h = harness();
  h.state.document.revision = "r2";
  await h.controller.submit(h.selected);
  assert.equal(h.requests.length, 0);
  assert.equal(h.state.selection, null);
  assert.deepEqual(h.state.paint, []);
  assert.equal(h.state.released, false);
});

test("source highlight paints before the response and survives success until publication", async () => {
  const h = harness();
  const pending = h.controller.submit(h.selected);
  assert.deepEqual(h.state.paint, [h.selected]);
  assert.equal(h.state.released, true);
  assert.equal(h.controller.pending, true);
  assert.equal(h.state.messages.at(-1), "하이라이트를 소스에 적용하는 중…");
  h.resolve({ status: "highlighted" });
  await pending;
  assert.deepEqual(h.state.paint, [h.selected]);
  assert.equal(h.state.selection, null);
  h.highlights.onDocument(JSON.stringify([undefined, "r2", undefined]));
  assert.deepEqual(h.state.paint, []);
});

test("rejected and disconnected highlights remove optimistic paint and retain retry text", async () => {
  for (const status of ["stale", "unsupported", "modified", "error", "offline"]) {
    const h = harness();
    const pending = h.controller.submit(h.selected);
    assert.deepEqual(h.state.paint, [h.selected]);
    if (status === "offline") h.reject();
    else h.resolve({ status });
    await pending;
    assert.deepEqual(h.state.paint, []);
    assert.equal(h.state.selection, status === "stale" ? null : h.selected);
  }
});

test("a service restart with the same revision cannot restore old retry context", async () => {
  const h = harness();
  const pending = h.controller.submit(h.selected);
  h.state.document.service = { pid: 8 };
  h.state.selection = null;
  h.highlights.onDocument(JSON.stringify([undefined, "r1", { pid: 8 }]));
  h.reject();
  await pending;
  assert.deepEqual(h.state.paint, []);
  assert.equal(h.state.retained, null);
});

test("terminal highlights carry editor identity and ordinary highlights omit the optional field", async () => {
  for (const expected of [undefined, "configured-editor"]) {
    const h = harness(expected);
    const pending = h.controller.submit(h.selected);
    const body = h.requests[0][1];
    assert.equal(body.editorServer, expected);
    assert.equal(Object.hasOwn(body, "editorServer"), expected !== undefined);
    h.resolve({ status: "modified" });
    await pending;
    assert.equal(h.state.selection, h.selected);
    assert.ok(h.state.messages.at(-1).includes("저장하지 않은"));
  }
});

test("shared editor highlights retain the private attachment through the HTML action", async () => {
  const h = harness("own-editor", "private-token");
  const pending = h.controller.submit(h.selected);
  assert.equal(h.requests[0][1].editorAttachment, "private-token");
  h.resolve({ status: "editor-mismatch" });
  await pending;
  assert.equal(h.state.selection, h.selected);
  assert.ok(h.state.messages.at(-1).includes("Neovim"));
});

function setGlobal(restorers, name, value) {
  const previous = Object.getOwnPropertyDescriptor(globalThis, name);
  Object.defineProperty(globalThis, name, {
    configurable: true,
    writable: true,
    value,
  });
  restorers.push(() => {
    if (previous) Object.defineProperty(globalThis, name, previous);
    else delete globalThis[name];
  });
}

function makeElement(tagName = "div") {
  const classes = new Set();
  const children = [];
  const element = Object.assign(new EventTarget(), {
    tagName,
    hidden: false,
    disabled: false,
    textContent: "",
    className: "",
    dataset: {},
    style: {},
    isConnected: false,
    classList: {
      add: (...names) => names.forEach((n) => classes.add(n)),
      remove: (...names) => names.forEach((n) => classes.delete(n)),
      toggle: (name, force) => {
        if (force === undefined) {
          if (classes.has(name)) classes.delete(name);
          else classes.add(name);
        } else if (force) classes.add(name);
        else classes.delete(name);
      },
    },
    setAttribute() {},
    removeAttribute() {},
    contains: () => false,
    querySelector: (selector) => (selector === "span" ? (children[0] ?? null) : null),
    querySelectorAll: () => [],
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 100, height: 20 }),
    append: (...nodes) => {
      for (const node of nodes) {
        node.isConnected = true;
        children.push(node);
      }
    },
    replaceChildren: (...nodes) => {
      children.length = 0;
      children.push(...nodes);
    },
    remove: () => {
      element.isConnected = false;
    },
  });
  return element;
}

function selectionControllerHarness(t) {
  const elements = new Map([
    ["#reader-selection", makeElement("div")],
    ["#reader-highlight-message", makeElement("div")],
    ["#reader-copy", makeElement("button")],
    ["#reader-source-highlight", makeElement("button")],
    ["#reader-chat-ask", makeElement("button")],
    ["#reader-strike", makeElement("button")],
    ["#reader-strike-undo", makeElement("button")],
    ["#reader-strike-clear", makeElement("button")],
    ["#reader-selection-cancel", makeElement("button")],
    ["#reader-highlight-results-clear", makeElement("button")],
    ["#reader-highlight-queue-status", makeElement("div")],
    ["#reader-review-actions", makeElement("div")],
    ["#reader-selection-actions", makeElement("div")],
    ["#reader-selection-hint", makeElement("div")],
  ]);
  elements.get("#reader-source-highlight").append(makeElement("span"));

  const doc = Object.assign(new EventTarget(), {
    activeElement: null,
    documentElement: makeElement("html"),
    querySelector: (selector) => elements.get(selector) ?? null,
    createElement: (tag) => makeElement(tag),
  });
  const win = Object.assign(new EventTarget(), {
    visualViewport: null,
    getSelection: () => ({ rangeCount: 0, isCollapsed: true, removeAllRanges() {} }),
  });
  const clipboardWrites = [];
  const restorers = [];
  setGlobal(restorers, "document", doc);
  setGlobal(restorers, "window", win);
  setGlobal(restorers, "navigator", {
    onLine: true,
    clipboard: {
      writeText: async (text) => {
        clipboardWrites.push(text);
      },
    },
  });
  setGlobal(
    restorers,
    "ResizeObserver",
    class {
      observe() {}
      disconnect() {}
    },
  );
  setGlobal(restorers, "requestAnimationFrame", () => 1);
  setGlobal(restorers, "cancelAnimationFrame", () => {});

  const article = makeElement("article");
  const controller = new ReaderSelectionActions(article, {
    createChat: () => ({
      pending: false,
      onDocument() {},
      submit() {},
      dismiss() {},
      dispose() {},
    }),
  });
  t.after(() => {
    controller.dispose();
    for (const restore of restorers.reverse()) restore();
  });

  let active = 0;
  let maxActive = 0;
  const requests = [];
  controller.transport.post = (path, body) => {
    active++;
    if (active > maxActive) maxActive = active;
    let resolve;
    let reject;
    const promise = new Promise((done, failed) => {
      resolve = (value) => {
        active--;
        done(value);
      };
      reject = (error) => {
        active--;
        failed(error);
      };
    });
    const record = { path, body, resolve, reject, settled: false };
    const origResolve = record.resolve;
    record.resolve = (value) => {
      record.settled = true;
      origResolve(value);
    };
    const origReject = record.reject;
    record.reject = (error) => {
      record.settled = true;
      origReject(error);
    };
    requests.push(record);
    return promise;
  };

  const manifest = { documentID: "pde-doc", revision: "r1" };
  controller.onDocument(manifest, null);
  return {
    controller,
    elements,
    manifest,
    requests,
    clipboardWrites,
    stats: () => ({ active, maxActive }),
  };
}

function makeMathFragments({
  blocks = 5,
  perBlock = [4, 4, 5, 4, 4],
  revision = "r1",
  prefix = "f",
} = {}) {
  const fragments = [];
  let index = 0;
  for (let b = 0; b < blocks; b++) {
    const count = perBlock[b] ?? 4;
    const segments = [];
    let offset = 0;
    for (let m = 0; m < count; m++) {
      const lead = `Block ${b} item ${m}: `;
      segments.push({ text: lead });
      offset += lead.length;
      const rendered = `${prefix}${index}`;
      const start = offset;
      const end = offset + rendered.length;
      segments.push({
        text: rendered,
        math: true,
        complete: true,
        start,
        end,
        prefix: lead.trim(),
        suffix: ".",
      });
      offset = end;
      segments.push({ text: ". " });
      offset += 2;
      index++;
    }
    const exact = segments.map((s) => s.text).join("");
    fragments.push({
      key: `block-${b}`,
      exact,
      start: 0,
      end: exact.length,
      revision,
      segments,
    });
  }
  return { fragments, total: index };
}

async function flushMicrotasks(turns = 4) {
  for (let i = 0; i < turns; i++) await Promise.resolve();
}

test("same-revision source-map recovery refetches unlocated formula excerpts without reloading", async (t) => {
  const h = selectionControllerHarness(t);
  const { fragments } = makeMathFragments({ blocks: 1, perBlock: [4] });
  h.controller.syncSourceMapStatus("unavailable");
  h.controller.selection = h.controller.copiedSelection = fragments;
  h.controller.prefetch(fragments);
  for (const [index, request] of h.requests.entries()) {
    request.resolve({ status: ["unmapped", "error", "stale", "located"][index], text: "$kept$" });
  }
  await flushMicrotasks();
  const located = [...h.controller.excerpts.values()].find((entry) => entry.status === "located");
  const generation = h.controller.excerptGeneration;

  h.controller.syncSourceMapStatus("verified");
  assert.equal(h.controller.manifest, h.manifest);
  assert.equal(h.manifest.revision, "r1");
  assert.equal(h.controller.selection, fragments);
  assert.ok(h.controller.excerptGeneration > generation);
  assert.equal(h.requests.length, 7);
  assert.ok([...h.controller.excerpts.values()].includes(located));
  assert.equal(h.controller.copyPending(fragments), true);
  for (const request of h.requests.slice(4)) {
    request.resolve({ status: "located", text: `$typst_${request.body.fragments[0].exact}$` });
  }
  await flushMicrotasks();
  assert.ok([...h.controller.excerpts.values()].every((entry) => entry.status === "located"));
  assert.equal(h.controller.copyPending(fragments), false);
  h.controller.syncSourceMapStatus("verified");
  assert.equal(h.requests.length, 7);
  h.controller.copySelection(fragments);
  await flushMicrotasks();
  assert.ok(h.clipboardWrites[0].includes("$typst_f0$"));
  assert.ok(h.clipboardWrites[0].includes("$kept$"));
});

test("partial source-map recovery resets pending batches and ignores their late responses", async (t) => {
  const h = selectionControllerHarness(t);
  const { fragments } = makeMathFragments({ blocks: 1, perBlock: [6] });
  h.controller.selection = h.controller.copiedSelection = fragments;
  h.controller.prefetch(fragments);
  const oldBatch = h.controller.excerptBatch;
  const oldRequests = [...h.requests];
  h.controller.syncSourceMapStatus("partial");
  assert.notEqual(h.controller.excerptBatch, oldBatch);
  assert.equal(oldBatch.queue.length, 0);
  const launched = h.requests.length;
  for (const request of oldRequests) request.resolve({ status: "unmapped" });
  await flushMicrotasks();
  assert.equal(h.requests.length, launched);
  assert.ok([...h.controller.excerpts.values()].every((entry) => entry.status === "pending"));
  while (h.requests.some((request) => !request.settled)) {
    for (const request of h.requests.filter((request) => !request.settled)) {
      request.resolve({ status: "located", text: "$recovered$" });
    }
    await flushMicrotasks();
  }
  assert.equal(h.controller.excerpts.size, 6);
  assert.ok([...h.controller.excerpts.values()].every((entry) => entry.text === "$recovered$"));
});

test("multi-block selection prefetches 21 formulas with bounded concurrency and copies Typst without fallback", async (t) => {
  const h = selectionControllerHarness(t);
  const { fragments, total } = makeMathFragments({ blocks: 5, perBlock: [4, 4, 5, 4, 4] });
  assert.equal(total, 21);

  h.controller.selection = fragments;
  h.controller.copiedSelection = fragments;
  h.controller.prefetch(fragments);
  h.controller.updateActions();

  assert.equal(h.controller.copyPending(fragments), true);
  assert.equal(h.elements.get("#reader-copy").disabled, true);
  assert.ok(h.requests.length > 0 && h.requests.length <= 6);
  assert.equal(h.stats().active, h.requests.length);

  let resolvedCount = 0;
  while (resolvedCount < total) {
    const next = h.requests.find((req) => !req.settled);
    assert.ok(next, `expected an active request at resolvedCount=${resolvedCount}`);
    const exact = next.body.fragments[0].exact;
    next.resolve({ status: "located", text: `$typst_${exact}$` });
    resolvedCount++;
    await flushMicrotasks();
    if (resolvedCount < total) {
      assert.equal(h.controller.copyPending(fragments), true);
      assert.equal(h.elements.get("#reader-copy").disabled, true);
    }
  }

  assert.equal(h.requests.length, total);
  assert.ok(h.stats().maxActive > 1 && h.stats().maxActive <= 6);
  assert.equal(h.controller.copyPending(fragments), false);
  assert.equal(h.elements.get("#reader-copy").disabled, false);

  h.controller.copySelection(fragments);
  await flushMicrotasks();

  assert.equal(h.clipboardWrites.length, 1);
  for (let i = 0; i < total; i++) {
    assert.ok(
      h.clipboardWrites[0].includes(`$typst_f${i}$`),
      `missing Typst source for formula f${i}`,
    );
  }
  const message = h.elements.get("#reader-highlight-message").textContent;
  assert.equal(message, "수식을 Typst 원문으로 복사했습니다.");
  assert.ok(!message.includes("화면에 표시된 글자"));
});

test("stale generation cancels remaining queued prefetches and ignores late responses", async (t) => {
  const h = selectionControllerHarness(t);
  const { fragments } = makeMathFragments({ blocks: 5, perBlock: [5, 4, 4, 4, 4] });

  h.controller.selection = fragments;
  h.controller.copiedSelection = fragments;
  h.controller.prefetch(fragments);
  const initialLaunched = h.requests.length;
  assert.ok(initialLaunched > 0 && initialLaunched < 21);
  assert.equal(h.controller.copyPending(fragments), true);

  let updateCalls = 0;
  const origUpdate = h.controller.updateActions.bind(h.controller);
  h.controller.updateActions = () => {
    updateCalls++;
    origUpdate();
  };

  h.controller.excerptGeneration++;
  assert.equal(h.controller.copyPending(fragments), false);

  for (const req of [...h.requests]) {
    req.resolve({ status: "located", text: "$stale$" });
  }
  await flushMicrotasks();

  assert.equal(h.requests.length, initialLaunched);
  assert.equal(updateCalls, 0);
  for (const entry of h.controller.excerpts.values()) {
    assert.notEqual(entry.status, "located");
    assert.notEqual(entry.text, "$stale$");
  }
});

test("selection and manifest changes cancel stale queued prefetches and serve the new selection cleanly", async (t) => {
  const h = selectionControllerHarness(t);
  const first = makeMathFragments({ blocks: 5, perBlock: [5, 4, 4, 4, 4], prefix: "old" });
  const second = makeMathFragments({ blocks: 1, perBlock: [2], prefix: "new" });

  h.controller.selection = first.fragments;
  h.controller.copiedSelection = first.fragments;
  h.controller.prefetch(first.fragments);
  const firstBatch = [...h.requests];
  assert.ok(firstBatch.length > 0 && firstBatch.length < 21);

  h.controller.selection = second.fragments;
  h.controller.copiedSelection = second.fragments;
  h.controller.prefetch(second.fragments);
  const secondBatch = h.requests.slice(firstBatch.length);
  assert.equal(secondBatch.length, 2);
  assert.equal(h.controller.copyPending(second.fragments), true);

  // Late responses from the previous selection are ignored and never launch remaining old items.
  for (const req of firstBatch) {
    req.resolve({ status: "located", text: "$old_late$" });
  }
  await flushMicrotasks();
  assert.equal(h.requests.length, firstBatch.length + 2);
  for (const entry of h.controller.excerpts.values()) {
    assert.notEqual(entry.text, "$old_late$");
  }

  for (const req of secondBatch) {
    const exact = req.body.fragments[0].exact;
    req.resolve({ status: "located", text: `$typst_${exact}$` });
  }
  await flushMicrotasks();
  assert.equal(h.controller.copyPending(second.fragments), false);

  h.controller.copySelection(second.fragments);
  await flushMicrotasks();
  assert.ok(h.clipboardWrites[0].includes("$typst_new0$"));
  assert.ok(h.clipboardWrites[0].includes("$typst_new1$"));
  assert.equal(
    h.elements.get("#reader-highlight-message").textContent,
    "수식을 Typst 원문으로 복사했습니다.",
  );

  // Revision mutation also cancels remaining queued prefetches and ignores late responses.
  const third = makeMathFragments({ blocks: 3, perBlock: [4, 4, 4], prefix: "rev" });
  const beforeThird = h.requests.length;
  h.controller.prefetch(third.fragments);
  const thirdLaunched = h.requests.slice(beforeThird);
  assert.ok(thirdLaunched.length > 0 && thirdLaunched.length < 12);

  h.manifest.revision = "r2";
  assert.equal(h.controller.copyPending(third.fragments), false);
  for (const req of thirdLaunched) {
    req.resolve({ status: "located", text: "$stale_rev$" });
  }
  await flushMicrotasks();
  assert.equal(h.requests.length, beforeThird + thirdLaunched.length);
  for (const entry of h.controller.excerpts.values()) {
    assert.notEqual(entry.text, "$stale_rev$");
  }
});

test("pathological selections cap prefetched formulas at a safe upper bound", async (t) => {
  const h = selectionControllerHarness(t);
  const huge = makeMathFragments({ blocks: 1, perBlock: [140], prefix: "huge" });

  h.controller.prefetch(huge.fragments);
  assert.equal(h.controller.copyPending(huge.fragments), true);

  let settled = 0;
  while (true) {
    const next = h.requests.find((req) => !req.settled);
    if (!next) break;
    const exact = next.body.fragments[0].exact;
    next.resolve({ status: "located", text: `$${exact}$` });
    settled++;
    await flushMicrotasks();
  }

  assert.equal(settled, 128);
  assert.equal(h.requests.length, 128);
  assert.equal(h.controller.copyPending(huge.fragments), false);
});

test("source highlight disables above 128 segments while staying enabled at 128 and keeping copy usable", (t) => {
  const h = selectionControllerHarness(t);
  const makeSegmented = (count, key = "block-0") => {
    const segments = Array.from({ length: count }, () => ({ text: "a" }));
    return {
      key,
      exact: "a".repeat(count),
      start: 0,
      end: count,
      revision: "r1",
      segments,
    };
  };

  const atLimit = [makeSegmented(128)];
  h.controller.selection = atLimit;
  h.controller.copiedSelection = atLimit;
  h.controller.updateActions();
  assert.equal(h.elements.get("#reader-source-highlight").disabled, false);
  assert.equal(h.elements.get("#reader-copy").disabled, false);

  const overLimit = [makeSegmented(129)];
  h.controller.selection = overLimit;
  h.controller.copiedSelection = overLimit;
  h.controller.updateActions();
  assert.equal(h.elements.get("#reader-source-highlight").disabled, true);
  assert.equal(h.elements.get("#reader-copy").disabled, false);

  const multiOverLimit = [makeSegmented(4, "block-0"), makeSegmented(129, "block-1")];
  h.controller.selection = multiOverLimit;
  h.controller.copiedSelection = multiOverLimit;
  h.controller.updateActions();
  assert.equal(h.elements.get("#reader-source-highlight").disabled, true);
  assert.equal(h.elements.get("#reader-copy").disabled, false);
});
