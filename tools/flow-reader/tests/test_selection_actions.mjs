import assert from "node:assert/strict";
import test from "node:test";
import { SourceHighlightController } from "../web/features/source-highlight/controller.js";
import { CodexContextController } from "../web/features/codex-context/controller.js";
import { OptimisticHighlights } from "../../reader-common/source-highlight/optimistic.js";

function harness(kind, editorServer) {
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
  controller =
    kind === "highlight"
      ? new SourceHighlightController(view, transport, highlights)
      : new CodexContextController(view, transport, 17);
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

for (const kind of ["highlight", "codex"]) {
  test(`${kind} acknowledgment preserves a newer selection or revision`, async () => {
    const h = harness(kind);
    const pending = h.controller.submit(h.selected);
    assert.equal(h.controller.pending, true);
    await h.controller.submit(h.selected);
    assert.equal(h.requests.length, 1);
    assert.equal(h.requests[0][0], kind === "highlight" ? "api/highlight" : "api/focus");
    if (kind === "codex") {
      assert.equal(h.requests[0][1].viewerID, 17);
      assert.deepEqual(h.requests[0][1].service, h.selected[0].service);
    }
    const newer = [{ ...h.selected[0], exact: "New selection" }];
    h.state.selection = newer;
    h.resolve(
      kind === "highlight"
        ? { status: "highlighted" }
        : { status: "selected", rendered_revision: "r1" },
    );
    await pending;
    assert.equal(h.state.selection, newer);
    assert.equal(h.controller.pending, false);
    const again = h.controller.submit(newer);
    h.state.document = { revision: "r2" };
    h.reject();
    await again;
    assert.equal(h.state.retained, null);
  });

  test(`${kind} failed submission retains a native collapsed range but respects dismissal`, async () => {
    const h = harness(kind);
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
}

test("source highlighting rejects a stale captured revision before writing", async () => {
  const h = harness("highlight");
  h.state.document.revision = "r2";
  await h.controller.submit(h.selected);
  assert.equal(h.requests.length, 0);
  assert.equal(h.state.selection, null);
  assert.deepEqual(h.state.paint, []);
  assert.equal(h.state.released, false);
});

test("source highlight paints before the response and survives success until publication", async () => {
  const h = harness("highlight");
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
    const h = harness("highlight");
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
  const h = harness("highlight");
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
    const h = harness("highlight", expected);
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
