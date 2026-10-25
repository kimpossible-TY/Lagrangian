import test from "node:test";
import assert from "node:assert/strict";
import {
  browserKey,
  graphicsProtocol,
  mousePosition,
  pngSequence,
  statusSequence,
  synchronizedOutput,
  TerminalInput,
  terminalSize,
} from "../terminal/protocol.mjs";
import { parseArguments, profileDefaults } from "../terminal/options.mjs";
import { serverArguments } from "../terminal/service.mjs";
import { EditorBridge } from "../terminal/editor-bridge.mjs";
import { TerminalReader } from "../terminal/host.mjs";
import { NativeTransport } from "../terminal/native-transport.mjs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { sessionOptions } from "../terminal/session.mjs";

test("fragmented UTF-8 and SGR drag events remain ordered", () => {
  const input = new TerminalInput();
  const bytes = Buffer.from("한\x1b[<0;12;9M\x1b[<32;18;9M\x1b[<0;18;9m");
  const actual = [];
  for (const byte of bytes) actual.push(...input.read(Buffer.from([byte])));
  assert.deepEqual(actual, [
    { type: "key", value: "한" },
    { type: "mouse", button: 0, column: 12, row: 9, released: false },
    { type: "mouse", button: 32, column: 18, row: 9, released: false },
    { type: "mouse", button: 0, column: 18, row: 9, released: true },
  ]);
});

test("pixel reports and escape keys do not become Reader shortcuts", () => {
  const input = new TerminalInput();
  assert.deepEqual(input.read(Buffer.from("\x1b[6;20;10t\x1b[4;800;1200t\x1b[A")), [
    { type: "geometry", kind: 6, height: 20, width: 10 },
    { type: "geometry", kind: 4, height: 800, width: 1200 },
    { type: "key", value: "\x1b[A" },
  ]);
  assert.deepEqual(input.read(Buffer.from("\x1b")), []);
  assert.deepEqual(input.flushEscape(), [{ type: "key", value: "\x1b" }]);
  assert.equal(browserKey("\x1b[Z"), "Shift+Tab");
});

test("bracketed paste is forwarded as text rather than executing Reader shortcuts", () => {
  const input = new TerminalInput();
  assert.deepEqual(input.read(Buffer.from("\x1b[200~h q")), []);
  assert.deepEqual(input.read(Buffer.from(" strike\x1b[201~j")), [
    { type: "paste", value: "h q strike" },
    { type: "key", value: "j" },
  ]);
});

test("mouse coordinates match image area and reject the status row", () => {
  const size = terminalSize(80, 25, 10, 20);
  assert.equal(size.height, 480);
  assert.deepEqual(mousePosition({ column: 1, row: 1 }, size), { x: 5, y: 10 });
  assert.deepEqual(mousePosition({ column: 80, row: 24 }, size), { x: 795, y: 470 });
  assert.equal(mousePosition({ column: 10, row: 25 }, size), null);
  assert.equal(mousePosition({ column: 0, row: 10 }, size), null);
});

test("Kitty image transport chunks payload without exceeding 4096 characters", () => {
  const size = terminalSize(80, 24);
  const png = Buffer.alloc(10000, 37);
  const output = pngSequence(png, size, "kitty");
  const chunks = [...output.matchAll(/\x1b_G([^;]*);([^\x1b]*)\x1b\\/g)];
  assert.equal(chunks.length, 4);
  assert.ok(chunks[0][1].includes("a=T,f=100"));
  assert.ok(chunks.slice(0, -1).every((chunk) => chunk[1].includes("m=1")));
  assert.equal(chunks.at(-1)[1], "m=0");
  assert.ok(chunks.every((chunk) => chunk[2].length <= 4096));
  assert.deepEqual(Buffer.from(chunks.map((chunk) => chunk[2]).join(""), "base64"), png);
});

test("iTerm image fills only the Reader rows and status rejects control injection", () => {
  const size = terminalSize(80, 24);
  const output = pngSequence(Buffer.from("PNG"), size, "iterm2");
  assert.ok(output.includes("width=80;height=23;preserveAspectRatio=0:"));
  assert.ok(output.endsWith("UE5H\x07"));
  assert.equal(
    statusSequence("hello\x1b[2J\nworld", size),
    "\x1b[24;1H\x1b[2K\x1b[?7lhello [2J world\x1b[?7h",
  );
  assert.equal(graphicsProtocol({ TERM_PROGRAM: "iTerm.app" }), "kitty");
  assert.equal(graphicsProtocol({ TERM: "xterm-kitty" }), "kitty");
  assert.equal(graphicsProtocol({ TERM: "xterm-256color" }), null);
  assert.equal(graphicsProtocol({ WT_SESSION: "client-pane" }), "sixel");
  assert.equal(graphicsProtocol({ TERM_PROGRAM: "Windows_Terminal" }), "sixel");
  assert.equal(parseArguments(["--protocol", "sixel"]).protocol, "sixel");
  assert.throws(() => parseArguments(["--protocol", "unknown"]), /protocol/);
});

test("editor sessions preserve RPC/lifecycle and allow only presentation overrides", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "flow-session-"));
  const control = path.join(directory, "editor.json");
  const args = [
    "--url",
    "http://127.0.0.1:23626/",
    "--editor-server",
    "/tmp/editor.sock",
    "--parent-pid",
    String(process.pid),
    "--control-file",
    control,
    "--profile",
    "/tmp/profile ' $()",
  ];
  const terminal = new URL("../terminal.mjs", import.meta.url);
  const record = { version: 1, args };
  try {
    await writeFile(control, JSON.stringify(record), { mode: 0o600 });
    const options = await sessionOptions(
      parseArguments(["--session", control, "--protocol", "sixel"]),
    );
    assert.equal(options.protocol, "sixel");
    assert.equal(options["editor-server"], "/tmp/editor.sock");
    assert.equal(options.profile, "/tmp/profile ' $()");
    assert.equal(options["control-file"], control);
    await assert.rejects(
      sessionOptions(parseArguments(["--session", control, "--root", directory])),
      /only/,
    );
    const help = execFileSync(
      process.execPath,
      [terminal.pathname, "--session", control, "--help"],
      { encoding: "utf8" },
    );
    assert.ok(help.includes("SIXEL"));
    assert.deepEqual(
      JSON.parse(await readFile(control)),
      record,
      "diagnosis must not consume a prepared session",
    );
    await writeFile(`${control}.attached`, "");
    assert.throws(
      () =>
        execFileSync(process.execPath, [terminal.pathname, "--session", control], {
          stdio: "pipe",
        }),
      (error) => error.stderr.toString().includes("already attached"),
    );
    assert.deepEqual(
      JSON.parse(await readFile(control)),
      record,
      "duplicate attachment must not stop the original host",
    );
    await rm(`${control}.attached`);
    assert.throws(
      () =>
        execFileSync(
          process.execPath,
          [terminal.pathname, "--session", control, "--protocol", "sixel"],
          { stdio: "pipe" },
        ),
      (error) => error.stderr.toString().includes("native terminal pane"),
    );
    await assert.rejects(readFile(control), /ENOENT/);
    await assert.rejects(readFile(`${control}.attached`), /ENOENT/);
    await assert.rejects(sessionOptions(parseArguments(["--session", control])), /ENOENT/);
    await writeFile(control, JSON.stringify({ version: 2, args }));
    await assert.rejects(sessionOptions(parseArguments(["--session", control])), /Invalid/);
    await writeFile(
      control,
      JSON.stringify({ version: 1, args: [...args, "--control-file", "/other/control"] }),
    );
    await assert.rejects(sessionOptions(parseArguments(["--session", control])), /lifecycle/);
    await writeFile(
      control,
      JSON.stringify({
        version: 1,
        args: [...args, "--parent-pid", String(Number.MAX_SAFE_INTEGER)],
      }),
    );
    await assert.rejects(
      sessionOptions(parseArguments(["--session", control])),
      /no longer running/,
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("argument validation prevents silent modes and preserves shell metacharacters", () => {
  assert.throws(() => parseArguments(["--port", "0"]), /Invalid --port/);
  assert.throws(() => parseArguments(["--root", "a", "--url", "http://localhost/"]), /either/);
  assert.throws(() => parseArguments(["--url", "file:///tmp/reader"]), /HTTP/);
  assert.throws(() => parseArguments(["--fps", "21"]), /Invalid/);
  assert.throws(() => parseArguments(["--unknown"]), /Unknown/);
  const options = parseArguments([
    "--root",
    "/tmp/space ' $()",
    "--compiler",
    "/tmp/typst `$()`",
    "--font-path",
    "one",
    "--font-path",
    "two",
  ]);
  const args = serverArguments(options);
  assert.equal(args[args.indexOf("--root") + 1], "/tmp/space ' $()");
  assert.equal(args[args.indexOf("--compiler") + 1], "/tmp/typst `$()`");
  assert.deepEqual(args.slice(-4), ["--font-path", "one", "--font-path", "two"]);
});

test("project profiles and origin ports are stable and isolated by entrypoint", () => {
  const first = profileDefaults({ root: "/tmp/project", entry: "main.typ" });
  assert.deepEqual(first, profileDefaults({ root: "/tmp/project", entry: "main.typ" }));
  assert.notEqual(
    first.profile,
    profileDefaults({ root: "/tmp/project", entry: "other.typ" }).profile,
  );
  assert.ok(first.port >= 45000 && first.port <= 59999);
});

test("one synchronized-update policy wraps only supported image frames", async () => {
  assert.equal(synchronizedOutput("IMG"), "\x1b[?2026hIMG\x1b[?2026l");
  const writes = [];
  const write = process.stdout.write;
  process.stdout.write = (chunk) => {
    writes.push(String(chunk));
    return true;
  };
  try {
    const size = terminalSize(80, 24);
    await new NativeTransport().present(
      { image: "IMG", sync: true, clear: true, status: "ready", size },
      new AbortController().signal,
    );
    assert.equal(writes[0], "\x1b[2J\x1b[H");
    assert.equal(writes[1], "\x1b[?2026hIMG\x1b[?2026l");
    assert.equal(writes[2], statusSequence("ready", size));
    writes.length = 0;
    await new NativeTransport().present(
      { image: "SIXEL", sync: false, clear: false, status: "ready", size },
      new AbortController().signal,
    );
    assert.equal(writes[0], "SIXEL");
  } finally {
    process.stdout.write = write;
  }
});

test("optional metrics record screenshot, encoding, bytes and unchanged signals", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "flow-metrics-"));
  const file = path.join(directory, "frames.jsonl");
  const png = Buffer.from("PNG-A");
  const changed = Buffer.from("PNG-B");
  const images = [png, png, changed];
  let index = 0;
  const page = {
    async setViewportSize() {},
    async evaluate() {
      return false;
    },
    async screenshot() {
      return images[Math.min(index++, images.length - 1)];
    },
  };
  const frames = [];
  const transport = {
    dimensions() {
      return [80, 24];
    },
    async open() {
      return () => {};
    },
    async present(frame) {
      frames.push(frame);
      return frame.image ? Buffer.byteLength(frame.image) : 0;
    },
  };
  const reader = new TerminalReader({ protocol: "kitty", metrics: file }, page, transport);
  try {
    reader.ready = true;
    await reader.capture();
    await reader.capture();
    await reader.capture();
  } finally {
    await reader.metrics.close();
  }
  const records = (await readFile(file, "utf8"))
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line));
  assert.equal(records.length, 3);
  assert.deepEqual(
    records.map((record) => record.unchanged),
    [false, true, false],
  );
  assert.deepEqual(
    records.map((record) => record.unchangedTotal),
    [0, 1, 1],
  );
  assert.ok(records[0].bytes > 0 && records[2].bytes > 0);
  assert.equal(records[1].bytes, 0);
  assert.equal(records[1].encodeMs, 0);
  assert.ok(records.every((record) => typeof record.screenshotMs === "number"));
  assert.ok(records.every((record) => typeof record.presentMs === "number"));
  assert.deepEqual(
    frames.map((frame) => frame.sync),
    [true, true, true],
  );
  await rm(directory, { recursive: true, force: true });
});

test("SIXEL frames stay unwrapped until physical terminal verification", async () => {
  const png = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==",
    "base64",
  );
  const frames = [];
  const reader = new TerminalReader(
    { protocol: "sixel" },
    {
      async setViewportSize() {},
      async evaluate() {
        return false;
      },
      async screenshot() {
        return png;
      },
    },
    {
      dimensions: () => [80, 24],
      async open() {
        return () => {};
      },
      async present(frame) {
        frames.push(frame);
        return frame.image.length;
      },
    },
  );
  reader.ready = true;
  await reader.capture();
  assert.equal(frames[0].sync, false);
  assert.ok(frames[0].image.startsWith('\x1b[H\x1bP0;1;0q"1;1;'));
});

test("cell geometry outranks full-window reports regardless of delivery order", async () => {
  const page = { async setViewportSize() {} };
  const cell = { type: "geometry", kind: 6, width: 9, height: 18 };
  const window = { type: "geometry", kind: 4, width: 1440, height: 900 };
  for (const sequence of [
    [cell, window],
    [window, cell],
  ]) {
    const reader = new TerminalReader({}, page);
    reader.isIterm = false;
    for (const event of sequence) await reader.event(event);
    assert.equal(reader.cellWidth, 9);
    assert.equal(reader.cellHeight, 18);
    assert.equal(reader.size.width, reader.size.columns * 9);
    assert.equal(reader.clearBeforeFrame, true);
  }
});

test("iTerm Retina report uses logical cell points and ignores whole-window dimensions", async () => {
  const input = new TerminalInput();
  const response = Buffer.from("\x1b]1337;ReportCellSize=18;9;2\x1b\\");
  const events = [];
  for (const byte of response) events.push(...input.read(Buffer.from([byte])));
  assert.deepEqual(events, [{ type: "geometry", kind: "iterm", width: 9, height: 18, scale: 2 }]);
  const reader = new TerminalReader({}, { async setViewportSize() {} });
  reader.isIterm = true;
  await reader.event({ type: "geometry", kind: 4, width: 1440, height: 900 });
  assert.equal(reader.cellWidth, 9);
  await reader.event({ type: "geometry", kind: 6, width: 18, height: 36 });
  await reader.event(events[0]);
  await reader.event({ type: "geometry", kind: 6, width: 18, height: 36 });
  await reader.event({ type: "geometry", kind: 4, width: 1440, height: 900 });
  assert.equal(reader.cellWidth, 9);
  assert.equal(reader.cellHeight, 18);
  assert.equal(reader.size.height, reader.size.imageRows * 18);
});

test("cursor baseline preserves restoration while moves and explicit sync still navigate", async (t) => {
  let cursor = { path: "/project/main.typ", line: 1, column: 0, modified: true };
  let requests = 0;
  let blocked = false;
  const page = {
    url: () => "http://127.0.0.1:23626/",
    async evaluate(_callback, location) {
      return location ? !blocked : false;
    },
    request: {
      async get() {
        return { json: async () => ({ revision: "current" }) };
      },
      async post() {
        requests++;
        return { ok: () => true, json: async () => ({ status: "located" }) };
      },
    },
  };
  const bridge = new EditorBridge({ "editor-server": "/editor.sock" }, page);
  bridge.rpc = async () => cursor;
  assert.equal(await bridge.cursor(), false);
  cursor.modified = false;
  assert.equal(await bridge.cursor(), false);
  assert.equal(requests, 0);
  cursor = { ...cursor, line: 7 };
  blocked = true;
  assert.equal(await bridge.cursor(), false);
  blocked = false;
  assert.equal(await bridge.cursor(), true);
  assert.equal(await bridge.cursor(), false);
  const work = await mkdtemp(path.join(tmpdir(), "flow-sync-test-"));
  t.after(() => rm(work, { recursive: true, force: true }));
  const sync = path.join(work, "sync.json");
  await writeFile(sync, JSON.stringify(cursor));
  const forced = new EditorBridge({ "sync-file": sync }, page);
  assert.equal(await forced.cursor(), true);
});

test("source navigation reports Neovim refusal rather than claiming cursor synchronization", async () => {
  const page = {
    async evaluate() {
      return { revision: "saved", fragments: [{ exact: "passage" }] };
    },
    url() {
      return "http://127.0.0.1:23626/?terminal=1";
    },
    request: {
      async post() {
        return {
          ok: () => true,
          async json() {
            return { status: "located", path: "/project/main.typ", line: 1, column: 0 };
          },
        };
      },
    },
  };
  const bridge = new EditorBridge({ "editor-server": "/editor.sock" }, page);
  bridge.rpc = async () => "modified";
  await assert.rejects(bridge.source(), /unsaved changes/);
  bridge.rpc = async () => "stale";
  await assert.rejects(bridge.source(), /Source changed/);
  bridge.rpc = async () => "error";
  await assert.rejects(bridge.source(), /no cursor was moved/);
  bridge.rpc = async () => "jumped";
  assert.equal(await bridge.source(), "jumped");
});

test("unknown Alt escape sequences cannot invoke Reader shortcuts", () => {
  const input = new TerminalInput();
  assert.deepEqual(input.read(Buffer.from("\x1bq")), []);
  assert.deepEqual(input.read(Buffer.from("\x1b")), []);
  assert.deepEqual(input.read(Buffer.from("h")), []);
  assert.deepEqual(input.read(Buffer.from("j")), [{ type: "key", value: "j" }]);
});

test("Kitty APC and DCS replies never become Reader shortcuts across read boundaries", () => {
  for (const reply of [
    "\x1b_Gi=39731;OK\x1b\\",
    "\x1b_Gi=39731;EINVAL:qhsug\x1b\\",
    "\x1bP1+r qhsug\x1b\\",
  ]) {
    const bytes = Buffer.from(reply);
    for (let split = 1; split <= bytes.length; split++) {
      const input = new TerminalInput();
      assert.deepEqual(input.read(bytes.subarray(0, split)), []);
      if (split > 1) assert.deepEqual(input.flushEscape(), []);
      assert.deepEqual(input.read(Buffer.concat([bytes.subarray(split), Buffer.from("j")])), [
        { type: "key", value: "j" },
      ]);
    }
    const input = new TerminalInput();
    for (const byte of bytes) assert.deepEqual(input.read(Buffer.from([byte])), []);
  }
});

test("accepted Reader actions clear an earlier terminal selection error", async () => {
  const page = {
    async evaluate(_callback, action) {
      return Boolean(action);
    },
  };
  const terminal = new TerminalReader({ protocol: "iterm2" }, page);
  const help = terminal.message;
  for (const value of ["h", "s", "u", "X"]) {
    terminal.message = "Select text to use that action";
    await terminal.event({ type: "key", value });
    assert.equal(terminal.message, help);
  }
});

test("explicit common change history and engine reach the owned Reader service", () => {
  const options = parseArguments([
    "--root",
    "/project",
    "--change-file",
    "/state/changes.json",
    "--engine",
    "/bin/flow-engine",
  ]);
  const args = serverArguments(options);
  assert.equal(args[args.indexOf("--change-file") + 1], "/state/changes.json");
  assert.equal(args[args.indexOf("--engine") + 1], "/bin/flow-engine");
});
