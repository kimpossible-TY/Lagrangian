import assert from "node:assert/strict";
import test from "node:test";
import { OptimisticHighlights } from "../source-highlight/optimistic.js";

test("optimistic paint survives acknowledgment and same-snapshot layout, then retires on render", () => {
  let painted;
  const highlights = new OptimisticHighlights((selections) => (painted = selections));
  const ticket = { selection: "selected text" };
  highlights.begin(ticket, "doc:r1:service1");
  assert.deepEqual(painted, [ticket.selection]);
  highlights.settle(ticket, "highlighted");
  highlights.onDocument("doc:r1:service1");
  highlights.repaint();
  assert.deepEqual(painted, [ticket.selection]);
  highlights.onDocument("doc:r2:service1");
  assert.deepEqual(painted, []);
});

test("late failures cannot clear another ticket or restore paint on a newer snapshot", () => {
  let painted;
  const highlights = new OptimisticHighlights((selections) => (painted = selections));
  const old = { selection: "old" };
  const current = { selection: "current" };
  highlights.begin(old, "r1");
  highlights.onDocument("r2");
  highlights.begin(current, "r2");
  highlights.settle(old, "error");
  highlights.settle(old, "highlighted");
  assert.deepEqual(painted, [current.selection]);
  highlights.settle(current, "unsupported");
  assert.deepEqual(painted, []);
});

test("consecutive highlights remain until replacement; rejection removes only its own paint", () => {
  let painted;
  const highlights = new OptimisticHighlights((selections) => (painted = selections));
  const saved = { selection: "saved" };
  const rejected = { selection: "rejected" };
  highlights.begin(saved, "r1");
  highlights.settle(saved, "highlighted");
  highlights.begin(rejected, "r1");
  assert.deepEqual(painted, [saved.selection, rejected.selection]);
  highlights.settle(rejected, "stale");
  assert.deepEqual(painted, [saved.selection]);
  highlights.dispose();
  assert.deepEqual(painted, []);
  highlights.begin(saved, "r1");
  highlights.repaint();
  assert.deepEqual(painted, []);
});
