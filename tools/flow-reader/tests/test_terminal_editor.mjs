import test from "node:test";
import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import { setTimeout as delay } from "node:timers/promises";
import { EditorTransport, editorLayout } from "../terminal/editor-transport.mjs";
import { TerminalReader } from "../terminal/host.mjs";

const layout = (generation, extra = {}) => ({
  version: 1,
  type: "resize",
  generation,
  columns: 40,
  rows: 24,
  cellWidth: 10,
  cellHeight: 20,
  visible: true,
  ...extra,
});

async function until(predicate) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await delay(10);
  }
  assert.fail("Editor transport did not make progress");
}

function fixture() {
  const input = new PassThrough();
  const output = new PassThrough();
  const messages = [];
  output.setEncoding("utf8");
  let pending = "";
  output.on("data", (chunk) => {
    pending += chunk;
    let end;
    while ((end = pending.indexOf("\n")) >= 0) {
      messages.push(JSON.parse(pending.slice(0, end)));
      pending = pending.slice(end + 1);
    }
  });
  const operations = [];
  const screencast = { listeners: new Set(), acks: [], starts: 0, stops: 0, startParams: null };
  const page = {
    context() {
      return {
        async newCDPSession() {
          return {
            on(event, listener) {
              if (event === "Page.screencastFrame") screencast.listeners.add(listener);
            },
            off(event, listener) {
              if (event === "Page.screencastFrame") screencast.listeners.delete(listener);
            },
            async send(method, params) {
              if (method === "Page.startScreencast") {
                screencast.starts++;
                screencast.startParams = params;
              } else if (method === "Page.stopScreencast") screencast.stops++;
              else if (method === "Page.screencastFrameAck") screencast.acks.push(params.sessionId);
            },
            async detach() {},
          };
        },
      };
    },
    async setViewportSize(size) {
      operations.push(["viewport", size]);
    },
    async evaluate() {
      return false;
    },
    async screenshot() {
      operations.push(["capture"]);
      return Buffer.from("PNG");
    },
    keyboard: {
      async insertText(text) {
        operations.push(["text", text]);
      },
      async press(key) {
        operations.push(["key", key]);
      },
    },
    mouse: {
      async move(x, y) {
        operations.push(["move", x, y]);
      },
      async down() {
        operations.push(["down"]);
      },
      async up() {
        operations.push(["up"]);
      },
      async wheel(x, y) {
        operations.push(["wheel", x, y]);
      },
    },
  };
  let frameSequence = 0;
  page.emitScreencast = () => {
    for (const listener of [...screencast.listeners])
      listener({ sessionId: ++frameSequence, data: Buffer.from(`frame-${frameSequence}`) });
  };
  const reader = new TerminalReader(
    { protocol: "kitty", fps: 20 },
    page,
    new EditorTransport(input, output),
  );
  const send = (message) => input.write(JSON.stringify({ version: 1, ...message }) + "\n");
  return { reader, page, input, messages, operations, send, screencast };
}

test("editor layouts reject invalid, unbounded and ambiguous dimensions", () => {
  assert.deepEqual(editorLayout(layout(1)), layout(1));
  for (const bad of [
    { generation: 0 },
    { columns: -1 },
    { rows: 1 },
    { cellWidth: 0 },
    { cellHeight: Infinity },
    { visible: "true" },
    { generation: 1.1 },
    { columns: 2000, rows: 1000, cellWidth: 200, cellHeight: 400 },
    { columns: 2000, rows: 2, cellWidth: 200, cellHeight: 1 },
  ])
    assert.throws(() => editorLayout(layout(1, bad)), /Invalid|limit/);
});

test("editor frame acknowledgment bounds capture and resize generations stay ordered", async () => {
  const f = fixture();
  const run = f.reader.run();
  try {
    f.send(layout(1));
    await until(() => f.messages.some((m) => m.type === "frame"));
    const first = f.messages.find((m) => m.type === "frame");
    assert.equal(first.generation, 1);
    assert.ok(first.image.startsWith("\x1b[?2026h\x1b[H\x1b_G"));
    await delay(140);
    assert.equal(f.operations.filter(([op]) => op === "capture").length, 1);
    f.send(layout(2, { columns: 50 }));
    f.send(layout(1, { columns: 2 })); // An obsolete resize cannot roll back state.
    f.send({ type: "ack", id: first.id });
    await until(() => f.messages.some((m) => m.type === "frame" && m.generation === 2));
    assert.equal(f.reader.size.width, 500);
    assert.equal(f.reader.size.height, 460);
    // EOF must release an unacknowledged frame and all timers/input references.
    f.input.end();
    await run;
    assert.equal(f.input.listenerCount("data"), 0);
    assert.equal(f.reader.stopped, true);
  } finally {
    f.reader.stop();
    await run;
  }
});

test("screencast frames merge while a frame awaits acknowledgment", async () => {
  const f = fixture();
  const run = f.reader.run();
  try {
    f.send(layout(1));
    await until(() => f.messages.some((m) => m.type === "frame"));
    const first = f.messages.find((m) => m.type === "frame");
    const captures = () => f.operations.filter(([op]) => op === "capture").length;
    f.page.emitScreencast();
    f.page.emitScreencast();
    f.page.emitScreencast();
    await delay(80);
    assert.equal(captures(), 1, "signals wait for the outstanding frame");
    f.send({ type: "ack", id: first.id });
    await until(() => f.messages.filter((m) => m.type === "frame").length === 2);
    await delay(150);
    assert.equal(f.messages.filter((m) => m.type === "frame").length, 2);
    assert.deepEqual(f.screencast.acks, [1, 2, 3]);
    assert.equal(f.screencast.starts, 1);
    assert.equal(
      f.screencast.startParams.maxWidth,
      undefined,
      "full-viewport signals keep Chromium's capture surface warm",
    );
  } finally {
    f.input.end();
    await run;
  }
  assert.equal(f.screencast.stops, 1);
  assert.equal(f.screencast.listeners.size, 0);
});

test("hidden layouts do not capture and showing the view forces a frame", async () => {
  const f = fixture();
  const run = f.reader.run();
  try {
    f.send(layout(1));
    await until(() => f.messages.some((m) => m.type === "frame"));
    const first = f.messages.find((m) => m.type === "frame");
    const captures = () => f.operations.filter(([op]) => op === "capture").length;
    f.send({ type: "ack", id: first.id });
    f.send(layout(2, { visible: false }));
    await delay(120);
    assert.equal(captures(), 1);
    f.send(layout(3, { columns: 50 }));
    await until(() => f.messages.some((m) => m.type === "frame" && m.generation === 3));
    assert.equal(captures(), 2);
    assert.equal(f.reader.size.width, 500);
  } finally {
    f.input.end();
    await run;
  }
});

test("a resize during a pending screenshot discards its obsolete frame", async () => {
  const f = fixture();
  let release;
  let blocking = true;
  f.page.screenshot = async () => {
    f.operations.push(["capture"]);
    if (blocking) {
      blocking = false;
      await new Promise((resolve) => {
        release = resolve;
      });
    }
    return Buffer.from("PNG");
  };
  const run = f.reader.run();
  try {
    f.send(layout(1));
    await until(() => f.operations.some(([op]) => op === "capture"));
    await f.reader.resize(layout(2, { columns: 50 }));
    release();
    await until(() => f.messages.some((m) => m.type === "frame"));
    assert.equal(f.messages.find((m) => m.type === "frame").generation, 2);
    assert.equal(f.reader.size.width, 500);
  } finally {
    f.input.end();
    await run;
  }
});

test("editor raw Unicode, paste, keys and drag use the existing browser controller", async () => {
  const f = fixture();
  const run = f.reader.run();
  try {
    f.send(layout(1));
    await until(() => f.messages.some((m) => m.type === "frame"));
    f.send({ type: "ack", id: 1 });
    f.send({
      type: "input",
      data: "한\x1b[200~h q\x1b[201~\x1b[A\x1b[<0;2;3M\x1b[<32;6;3M\x1b[<0;6;3m",
    });
    await until(() => f.operations.some(([op]) => op === "up"));
    assert.deepEqual(
      f.operations.filter(([op]) => op !== "capture" && op !== "viewport"),
      [
        ["text", "한"],
        ["text", "h q"],
        ["key", "ArrowUp"],
        ["move", 15, 50],
        ["down"],
        ["move", 55, 50],
        ["move", 55, 50],
        ["up"],
      ],
    );
    f.send({ type: "input", data: "q" });
    await run;
    assert.equal(f.input.readableFlowing, false);
  } finally {
    f.reader.stop();
    await run;
  }
});

test("invalid editor messages and cancellation during handshake release the host", async () => {
  for (const message of [{ version: 2, type: "resize" }, layout(1, { rows: -1 })]) {
    const f = fixture();
    const run = f.reader.run();
    f.send(message);
    await run;
    assert.equal(f.messages.at(-1).type, "error");
    assert.equal(f.reader.stopped, true);
  }
  const f = fixture();
  const run = f.reader.run();
  f.reader.stop();
  await run;
  assert.equal(f.input.listenerCount("data"), 0);
});
