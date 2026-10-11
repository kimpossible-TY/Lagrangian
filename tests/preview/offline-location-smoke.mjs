// Real filesystem edits with no viewers; only disposable Git sources and ports.
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import WebSocket from "ws";

const engine = process.argv[2];
assert.ok(engine, "pass the engine executable");
const temp = await realpath(await mkdtemp(resolve(tmpdir(), "flow-offline-location-")));
let child,
  address,
  logs = "";
const sockets = new Set();
const record = async () => JSON.parse(await readFile(resolve(temp, "changes.json"), "utf8"));
async function until(predicate, label) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    if (child?.exitCode !== null) throw new Error(logs.slice(-3000));
    await delay(40);
  }
  throw new Error(`Timed out: ${label}\n${logs.slice(-3000)}`);
}
async function start() {
  logs = "";
  child = spawn(
    engine,
    [
      "preview",
      resolve(temp, "main.typ"),
      "--root",
      temp,
      "--no-open",
      "--follow-system-theme",
      "--partial-rendering=true",
      "--data-plane-host=127.0.0.1:0",
      "--control-plane-host=127.0.0.1:0",
    ],
    {
      env: {
        ...process.env,
        TINYMIST_ALLOWED_ORIGINS: "",
        TINYMIST_PREVIEW_CHANGE_FILE: resolve(temp, "changes.json"),
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  child.stdout.on("data", (data) => (logs += data));
  child.stderr.on("data", (data) => (logs += data));
  await until(
    () => (address = /Data plane server listening on: (127\.0\.0\.1:\d+)/.exec(logs)?.[1]),
    "listener",
  );
}
async function stop() {
  for (const socket of sockets) socket.terminate();
  sockets.clear();
  if (!child || child.exitCode !== null) return;
  const exit = new Promise((done) => child.once("exit", done));
  child.kill("SIGINT");
  await Promise.race([exit, delay(3000)]);
  if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
  await exit;
}
async function connect(theme, page) {
  const ws = new WebSocket(`ws://${address}/_theme/${theme}`, { origin: `http://${address}` });
  const frames = [];
  ws.on("message", (data) => {
    const comma = data.indexOf(44);
    frames.push({
      type: data.subarray(0, comma).toString(),
      payload: data.subarray(comma + 1).toString(),
    });
  });
  ws.on("error", () => {});
  sockets.add(ws);
  await until(() => ws.readyState === WebSocket.OPEN, "socket");
  ws.send("current");
  await until(() => frames.some((frame) => frame.type === "new"), "document");
  const hint = frames.findLast((frame) => frame.type === "resume" || frame.type === "change");
  assert.ok(hint, `${theme} should restore a tracked edit`);
  assert.equal(
    Number(hint.payload.split(" ")[0]),
    page,
    `${theme} must map the latest offline edit into its own layout, ahead of older Git changes`,
  );
  return ws;
}
function git(...args) {
  execFileSync("git", [
    "-C",
    temp,
    "-c",
    "core.hooksPath=/dev/null",
    "-c",
    "commit.gpgsign=false",
    "-c",
    "user.name=Test",
    "-c",
    "user.email=test@example.invalid",
    ...args,
  ]);
}
try {
  git("init", "-q");
  await writeFile(resolve(temp, ".gitignore"), "changes.json\n");
  await writeFile(
    resolve(temp, "main.typ"),
    `#set page(width: 400pt, height: 500pt)
Cover
#if sys.inputs.at("theme", default: "light") == "dark" { pagebreak(); [Dark layout extra page] }
#pagebreak()
#outline()
#pagebreak()
#include "earlier.typ"
#pagebreak()
Separator
#pagebreak()
#include "later.typ"
`,
  );
  await writeFile(resolve(temp, "earlier.typ"), "Original early body.\n");
  const later = (first, second) =>
    `= ${first}\nLate body.\n#pagebreak()\n= ${second}\nSecond body.\n`;
  await writeFile(
    resolve(temp, "later.typ"),
    later("Original late heading", "Original second heading"),
  );
  git("add", ".");
  git("commit", "-qm", "baseline");
  await writeFile(resolve(temp, "earlier.typ"), "Older cumulative Git change.\n");
  await start();
  const light = await connect("light", 3);
  await delay(500);
  light.terminate();
  sockets.delete(light);
  await delay(300);
  const idle = JSON.stringify((await record()).variants);
  await writeFile(resolve(temp, "earlier.typ"), "First edit with no viewers.\n");
  await delay(500);
  await writeFile(
    resolve(temp, "later.typ"),
    later("Latest offline heading", "Original second heading"),
  );
  await until(
    async () => (await record()).source_history?.latest?.filepath === resolve(temp, "later.typ"),
    "idle source observation",
  );
  assert.equal(
    JSON.stringify((await record()).variants),
    idle,
    "idle saves do not compile either palette",
  );
  const dark = await connect("dark", 6); // This theme has never compiled.
  dark.terminate();
  sockets.delete(dark);
  await delay(300);
  await stop();
  await start();
  await connect("light", 5);
  await connect("dark", 6);
  for (const socket of sockets) socket.terminate();
  sockets.clear();
  await delay(300);
  const sequence = (await record()).source_history.sequence;
  await writeFile(
    resolve(temp, "later.typ"),
    later("Newer first heading", "Original second heading"),
  );
  await until(
    async () => (await record()).source_history.sequence > sequence,
    "first same-file save",
  );
  const newer = (await record()).source_history.sequence;
  await writeFile(
    resolve(temp, "later.typ"),
    later("Newer first heading", "Newest second heading"),
  );
  await until(
    async () => (await record()).source_history.sequence > newer,
    "latest same-file save",
  );
  await stop();
  await start();
  await connect("dark", 7);
  await connect("light", 6);
  console.log(
    "PASS: viewer-free edit order across files and within one file, no idle layout, cold theme with different pagination, body over outline, restart and Git fallback precedence",
  );
} finally {
  await stop();
  await rm(temp, { recursive: true, force: true });
}
