import assert from "node:assert/strict";
import test from "node:test";
import { DraftRecovery } from "../web/features/paragraph-chat/draft-recovery.js";

const storage = () => {
  const values = new Map();
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => values.delete(key),
  };
};
const record = (draft = "", thread = []) => ({ conversation_id: "conversation", draft, thread });

test("tab recovery survives a new controller and stays document/conversation bound", () => {
  const tab = storage();
  const first = new DraftRecovery(() => tab);
  assert.equal(first.set("document", "conversation", "미저장 초안 🧮", "pending-message"), true);
  const reopened = new DraftRecovery(() => tab);
  assert.deepEqual(reopened.get("document", "conversation"), {
    text: "미저장 초안 🧮",
    messageID: "pending-message",
  });
  assert.equal(reopened.get("other-document", "conversation"), null);
  assert.equal(reopened.get("document", "other-conversation"), null);
});

test("draft acknowledgment does not discard newer local text or a different host draft", () => {
  const tab = storage();
  const recovery = new DraftRecovery(() => tab);
  recovery.set("document", "conversation", "new local draft");
  assert.equal(recovery.acknowledge("document", record("different host draft")), null);
  assert.equal(recovery.acknowledge("document", record("older local draft")), null);
  assert.equal(recovery.get("document", "conversation").text, "new local draft");
  assert.ok(recovery.acknowledge("document", record("new local draft")));
  assert.equal(recovery.get("document", "conversation"), null);
  assert.equal(new DraftRecovery(() => tab).get("document", "conversation"), null);
});

test("accepted sends reconcile by message identity rather than repeated question text", () => {
  const recovery = new DraftRecovery(storage);
  recovery.set("document", "conversation", "same question", "pending-message");
  assert.equal(
    recovery.acknowledge(
      "document",
      record("", [{ id: "older-message", role: "user", text: "same question" }]),
    ),
    null,
  );
  assert.equal(
    recovery.acknowledge(
      "document",
      record("", [{ id: "pending-message", role: "assistant", text: "same question" }]),
    ),
    null,
  );
  assert.equal(
    recovery.acknowledge(
      "document",
      record("", [{ id: "pending-message", role: "user", text: "different question" }]),
    ),
    null,
  );
  assert.ok(
    recovery.acknowledge(
      "document",
      record("", [{ id: "pending-message", role: "user", text: "same question" }]),
    ),
  );
  assert.equal(recovery.get("document", "conversation"), null);
});

test("clearing a draft is recoverable and acknowledgment removal failures cannot resurrect text", () => {
  const tab = storage();
  const recovery = new DraftRecovery(() => tab);
  recovery.set("document", "conversation", "");
  assert.deepEqual(new DraftRecovery(() => tab).get("document", "conversation"), { text: "" });
  tab.removeItem = () => {
    throw new Error("denied");
  };
  assert.ok(recovery.acknowledge("document", record("")));
  assert.equal(recovery.get("document", "conversation"), null);
  const reopened = new DraftRecovery(() => tab);
  assert.ok(reopened.acknowledge("document", record("")));
  assert.equal(reopened.get("document", "conversation"), null);
});

test("invalid/oversized recovery data is ignored and extra fields never enter the recovered value", () => {
  const tab = storage();
  const key = new DraftRecovery().key("document", "conversation");
  assert.equal(
    new DraftRecovery(() => tab).set("document", "conversation", "x".repeat(8001)),
    false,
  );
  for (const value of [
    "{",
    JSON.stringify({ text: "x".repeat(8001) }),
    JSON.stringify({ text: "draft", messageID: 1 }),
    " ".repeat(65537),
  ]) {
    tab.setItem(key, value);
    assert.equal(new DraftRecovery(() => tab).get("document", "conversation"), null);
  }
  tab.setItem(
    key,
    JSON.stringify({ text: "literal <script>", secret: "not recovered", source: "/private/path" }),
  );
  assert.deepEqual(new DraftRecovery(() => tab).get("document", "conversation"), {
    text: "literal <script>",
  });
});

test("unavailable tab storage retains the current memory copy and reports failed persistence", () => {
  const recovery = new DraftRecovery(() => {
    throw new Error("storage unavailable");
  });
  assert.equal(recovery.set("document", "conversation", "keep editing"), false);
  assert.deepEqual(recovery.get("document", "conversation"), { text: "keep editing" });
  assert.ok(recovery.acknowledge("document", record("keep editing")));
  assert.equal(recovery.get("document", "conversation"), null);
});
