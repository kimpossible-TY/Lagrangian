import assert from "node:assert/strict";
import test from "node:test";
import { SourceHighlightController } from "../web/features/source-highlight/controller.js";
import { CodexContextController } from "../web/features/codex-context/controller.js";

function harness(kind) {
  const selected = [{ key: "body", exact: "Selected", revision: "r1", service: { pid: 7 } }];
  const state = {
    document: { revision: "r1" },
    selection: selected,
    retained: null,
    messages: [],
    changes: 0,
  };
  let resolve;
  let reject;
  const requests = [];
  let controller;
  const view = {
    document: () => state.document,
    selection: () => state.selection,
    sameSelection: (left, right) => JSON.stringify(left) === JSON.stringify(right),
    enabled: () => !controller.pending,
    collapse: () => {
      controller.dismiss();
      state.selection = null;
      state.retained = null;
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
  controller =
    kind === "highlight"
      ? new SourceHighlightController(view, transport)
      : new CodexContextController(view, transport, 17);
  return {
    state,
    selected,
    requests,
    controller,
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
});
