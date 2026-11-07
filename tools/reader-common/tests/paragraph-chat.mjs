import assert from "node:assert/strict";
import test from "node:test";
import { ConversationState, conversationSummary } from "../paragraph-chat/state.js";

const snapshot = { documentID: "doc", revision: "r1", service: { pid: 1, startedAt: 2 } };
const record = (id, version = 0, sequence = 0) => ({
  conversation_id: id,
  version,
  sequence,
  quote: "A selected paragraph",
  status: "idle",
  thread: [],
});

test("chat adoption rejects old revisions, service restarts and late stream frames", () => {
  const state = new ConversationState();
  state.document(snapshot);
  const generation = state.generation;
  assert.ok(state.accept({ ...snapshot, conversations: [record("a", 2, 3), record("b")] }));
  state.accept({ ...snapshot, conversations: [record("a", 2, 1)] });
  assert.equal(state.records.get("a").sequence, 3);
  state.accept({ ...snapshot, conversations: [record("a", 1, 5)] });
  assert.equal(state.records.get("a").version, 2);
  assert.equal(state.records.get("b").version, 0);
  state.document({ ...snapshot, service: { pid: 9 } });
  assert.equal(state.accept({ ...snapshot, conversations: [record("a")] }, generation), false);
  assert.equal(state.records.size, 0);
});

test("summary uses the latest literal question and actual answer with honest partial status", () => {
  const value = record("a");
  assert.equal(conversationSummary(value), "A selected paragraph");
  value.thread = [
    { role: "user", text: "First question?", status: "completed" },
    { role: "assistant", text: "First answer", status: "completed" },
    { role: "user", text: "A newer question?", status: "completed" },
    { role: "assistant", text: "The real latest answer", status: "failed" },
  ];
  assert.equal(conversationSummary(value), "A newer question? · Partial: The real latest answer");
  value.thread[3].status = "completed";
  assert.equal(conversationSummary(value), "A newer question? · The real latest answer");
});


test("summary strips paired bold and math before truncating, preserving literal markers", () => {
  const value = record("bold");
  value.quote = "**" + "a".repeat(139) + "**";
  assert.equal(conversationSummary(value), "a".repeat(139));
  value.thread = [
    { role: "user", text: "**Value $x^2$** and __price__ $5-$10", status: "completed" },
    { role: "assistant", text: "Unmatched ** and \\*\\*literal\\*\\* US$5–US$10", status: "completed" },
  ];
  assert.equal(conversationSummary(value), "Value x^2 and price $5-$10 · Unmatched ** and \\*\\*literal\\*\\* US$5–US$10");
});
