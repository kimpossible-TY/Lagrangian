import assert from "node:assert/strict";
import test from "node:test";
import { HighlightIntents } from "../web/features/source-highlight/intents.js";

class Storage {
  data = new Map();
  get length() {
    return this.data.size;
  }
  key(index) {
    return [...this.data.keys()][index];
  }
  getItem(key) {
    return this.data.get(key) ?? null;
  }
  setItem(key, value) {
    this.data.set(key, value);
  }
  removeItem(key) {
    this.data.delete(key);
  }
}
const payload = {
  documentID: "document",
  revision: "r1",
  service: { pid: 7, startedAt: 1 },
  fragments: [{ key: "p", exact: "Selected text", revision: "r1" }],
};

function fixture() {
  const state = { online: false, calls: [], status: "highlighted", sequence: 0 };
  const storage = new Storage();
  const options = {
    storage,
    prefix: "intents:",
    online: () => state.online,
    identity: () => `request-${++state.sequence}-1234567890`,
    transport: {
      async post(path, request) {
        state.calls.push(structuredClone(request));
        if (state.fail) throw new Error("Lost acknowledgment");
        return { status: state.status, revision: request.revision };
      },
    },
  };
  return { state, storage, options, queue: new HighlightIntents(options) };
}

test("offline intent survives a new page and retains its original identity and snapshot", async () => {
  const f = fixture();
  const original = structuredClone(payload);
  assert.equal((await f.queue.submit(original)).status, "queued");
  original.revision = "newer";
  original.fragments[0].exact = "Changed selection";
  f.queue.dispose();
  assert.equal(f.state.calls.length, 0);
  const recovered = new HighlightIntents(f.options);
  const request = recovered.records("document")[0].request;
  f.state.online = true;
  await recovered.flush("document");
  assert.deepEqual(f.state.calls, [request]);
  assert.equal(request.revision, "r1");
  assert.equal(request.fragments[0].exact, "Selected text");
  assert.equal(recovered.records("document").length, 0);
});

test("lost response retries the same request while another document stays isolated", async () => {
  const f = fixture();
  f.state.online = true;
  f.state.fail = true;
  assert.equal((await f.queue.submit(payload)).status, "queued");
  await f.queue.submit({ ...payload, documentID: "another" });
  f.state.fail = false;
  await f.queue.flush("document");
  assert.deepEqual(f.state.calls[0], f.state.calls[2]);
  assert.equal(f.queue.records("another").length, 1);
});

test("server conflicts and uncertain receipts require review and never auto-retry", async () => {
  for (const status of ["stale", "uncertain", "editor-mismatch", "modified"]) {
    const f = fixture();
    await f.queue.submit(payload);
    f.state.online = true;
    f.state.status = status;
    await f.queue.flush("document");
    await f.queue.flush("document");
    assert.equal(f.state.calls.length, 1);
    assert.equal(f.queue.records("document")[0].result.status, status);
    f.queue.clearRejected("document");
    assert.equal(f.queue.records("document").length, 0);
  }
});

test("storage failure prevents dispatch and cannot claim an offline queue exists", async () => {
  const f = fixture();
  f.state.online = true;
  f.storage.setItem = () => {
    throw new Error("Quota exceeded");
  };
  await assert.rejects(f.queue.submit(payload), /Quota/);
  assert.equal(f.state.calls.length, 0);
});

test("independent tab keys do not overwrite requests and pending requests cannot be cleared as results", async () => {
  const f = fixture();
  const other = new HighlightIntents(f.options);
  await Promise.all([f.queue.submit(payload), other.submit(payload)]);
  assert.equal(f.queue.records("document").length, 2);
  f.queue.clearRejected("document");
  assert.equal(f.queue.records("document").length, 2);
});

test("concurrent refreshes share an in-flight dispatch and disposal prevents later dispatch", async () => {
  const f = fixture();
  let complete;
  f.options.transport.post = (path, request) => {
    f.state.calls.push(request);
    return new Promise((resolve) => {
      complete = resolve;
    });
  };
  await f.queue.submit(payload);
  f.state.online = true;
  const first = f.queue.flush("document");
  const second = f.queue.flush("document");
  assert.equal(f.state.calls.length, 1);
  f.queue.dispose();
  complete({ status: "highlighted" });
  await Promise.all([first, second]);
  assert.equal(f.queue.records("document").length, 0);
  await f.queue.flush("document");
  assert.equal(f.state.calls.length, 1);
});

test("failed acknowledgment cleanup replays its durable ID instead of creating another edit", async () => {
  const f = fixture();
  f.state.online = true;
  const remove = f.storage.removeItem.bind(f.storage);
  f.storage.removeItem = () => {
    throw new Error("Storage unavailable");
  };
  assert.equal((await f.queue.submit(payload)).status, "highlighted");
  f.storage.removeItem = remove;
  await f.queue.flush("document");
  assert.deepEqual(f.state.calls[0], f.state.calls[1]);
});
