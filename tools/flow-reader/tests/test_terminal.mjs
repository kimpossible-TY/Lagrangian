import test from "node:test";
import assert from "node:assert/strict";
import {
  browserKey,
  graphicsProtocol,
  mousePosition,
  pngSequence,
  statusSequence,
  TerminalInput,
  terminalSize,
} from "../terminal/protocol.mjs";
import { parseArguments, profileDefaults } from "../terminal/options.mjs";
import { serverArguments } from "../terminal/service.mjs";
import { EditorBridge } from "../terminal/editor-bridge.mjs";
import { TerminalReader } from "../terminal/host.mjs";

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
