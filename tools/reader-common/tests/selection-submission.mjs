import assert from "node:assert/strict";
import test from "node:test";
import { SelectionSubmission } from "../selection/submission.js";

for (const [name, selected, changed] of [
  [
    "paged",
    { revision: "a", start: { page: 1, x: 10, y: 20 } },
    { revision: "a", start: { page: 2, x: 10, y: 20 } },
  ],
  [
    "semantic HTML",
    [{ key: "paragraph", start: 10, end: 20 }],
    [{ key: "paragraph", start: 30, end: 40 }],
  ],
]) {
  test(`${name} submission retains renderer identity and rejects obsolete acknowledgments`, () => {
    const state = new SelectionSubmission((a, b) => JSON.stringify(a) === JSON.stringify(b));
    const ticket = state.begin(selected, "a");
    assert.equal(ticket.selection, selected);
    assert.equal(state.begin(changed, "a"), undefined);
    assert.equal(state.canApply(ticket, selected, "a"), true);
    assert.equal(state.canApply(ticket, structuredClone(selected), "a"), true);
    assert.equal(state.canApply(ticket, changed, "a"), false);
    assert.equal(state.canApply(ticket, selected, "b"), false);
    assert.equal(state.canApply(ticket, null, "a"), true);
    assert.equal(state.canApply(ticket, null, "a", false), false);
    state.dismiss();
    assert.equal(state.canApply(ticket, selected, "a"), false);
    state.finish(ticket);
    const retry = state.begin(selected, "a");
    state.finish(ticket);
    assert.equal(state.pending, retry);
    state.finish(retry);
    assert.equal(state.pending, undefined);
  });
}
