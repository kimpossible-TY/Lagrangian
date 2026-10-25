// Real HTML Reader + terminal browser host + disposable Neovim integration.
import assert from "node:assert/strict";
import { spawn, execFile } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readFile, rm, mkdir, realpath, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { openReader, waitForReader } from "../terminal/browser-session.mjs";
import { EditorBridge } from "../terminal/editor-bridge.mjs";
import { TerminalReader } from "../terminal/host.mjs";
import { sixelSequence } from "../terminal/sixel.mjs";
import { startReader } from "../terminal/service.mjs";

const exec = promisify(execFile);
const work = await mkdtemp(path.join(tmpdir(), "flow-terminal-test-"));
const address = path.join(work, "editor.sock");
const changeFile = path.join(work, "changes.json");
const repository = fileURLToPath(new URL("../../..", import.meta.url));
const fixture = spawn(
  process.env.PYTHON || "python3",
  [fileURLToPath(new URL("./selection_fixture.py", import.meta.url))],
  {
    env: {
      ...process.env,
      FLOW_READER_MANAGED_FIXTURE: "1",
      FLOW_READER_CHANGE_FILE: changeFile,
    },
    stdio: ["ignore", "pipe", "inherit"],
  },
);
const lines = createInterface({ input: fixture.stdout });
const fixtureReady = Promise.race([
  once(lines, "line").then(([line]) => JSON.parse(line)),
  once(fixture, "exit").then(([code]) => {
    throw new Error(`Reader fixture exited ${code}`);
  }),
]);
let editor;
let host;
let reader;
const priorPython = process.env.PYTHON;
const priorData = process.env.FLOW_READER_DATA_DIR;
let checks = 0;
const check = (description, value) => {
  assert.ok(value, description);
  checks++;
  console.log(`✓ ${description}`);
};
const vimString = (value) => `'${String(value).replaceAll("'", "''")}'`;
async function rpc(lua, payload = null) {
  const expression = `json_encode(luaeval(${vimString(lua)},json_decode(${vimString(JSON.stringify(payload))})))`;
  const { stdout } = await exec(
    process.env.NVIM || "nvim",
    ["--server", address, "--remote-expr", expression],
    { timeout: 2500 },
  );
  return JSON.parse(stdout);
}
async function stop(child) {
  if (!child || child.exitCode !== null || child.signalCode !== null) return;
  const exited = once(child, "exit");
  child.kill("SIGTERM");
  await exited;
}
try {
  const { url, entry, focusFile, managedData, managerPython } = await fixtureReady;
  process.env.FLOW_READER_DATA_DIR = managedData;
  process.env.PYTHON = managerPython;
  editor = spawn(
    process.env.NVIM || "nvim",
    [
      "--headless",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "--listen",
      address,
      "--cmd",
      "lua vim.opt.rtp:append(vim.env.FLOW_TEST_PLUGIN)",
      "--cmd",
      "lua require('tinymist.reader').setup({auto_open=false,root=vim.env.FLOW_TEST_ROOT})",
      "--",
      entry,
    ],
    {
      env: {
        ...process.env,
        FLOW_TEST_PLUGIN: path.join(repository, "editors/neovim"),
        FLOW_TEST_ROOT: path.dirname(entry),
      },
      stdio: "ignore",
    },
  );
  for (let attempt = 0; ; attempt++) {
    try {
      await rpc("require('tinymist.reader').cursor()");
      break;
    } catch (error) {
      if (attempt > 40 || editor.exitCode !== null) throw error;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  const options = {
    root: path.dirname(entry),
    entry,
    profile: path.join(work, "browser"),
    "editor-server": address,
  };
  reader = await startReader(options);
  options["editor-attachment"] = reader.editorAttachment;
  check("Project presentation resolves the existing managed HTML service", reader.url === url);
  host = await openReader(options, { width: 760, height: 700 });
  const page = host.page;
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await waitForReader(page, url, options);
  await page.waitForFunction(() => globalThis.flowReaderTerminal?.state().ready);
  const screenshot = await page.screenshot({ type: "png", scale: "css" });
  const sixel = sixelSequence(screenshot);
  check(
    "Real Chromium viewport encodes as native SIXEL with matching geometry",
    sixel.startsWith('\x1b[H\x1bP0;1;0q"1;1;760;700') && sixel.endsWith("\x1b\\"),
  );
  const original = await readFile(entry, "utf8");
  const bridge = new EditorBridge(options, page);
  check("Initial cursor polling preserves the Reader destination", !(await bridge.cursor()));
  const beforeChange = await (await page.request.get(url + "api/state")).json();
  const editStart = original.indexOf("Trailing paragraph 13");
  const sourcePath = await realpath(entry);
  const sourceRoot = path.dirname(sourcePath);
  await writeFile(
    changeFile,
    JSON.stringify({
      schema_version: 2,
      project: JSON.stringify([sourceRoot, sourcePath]),
      variants: {},
      source_history: {
        sequence: 7,
        sources: { [sourcePath]: original },
        latest: {
          filepath: sourcePath,
          source_hash: "a".repeat(32),
          range: {
            start: Buffer.byteLength(original.slice(0, editStart)),
            end: Buffer.byteLength(original.slice(0, editStart + "Trailing paragraph 13".length)),
          },
        },
      },
    }),
  );
  await page.waitForFunction(
    () => {
      const target = [...document.querySelectorAll("#reader-document p")].find((node) =>
        node.textContent.startsWith("Trailing paragraph 13"),
      );
      const rect = target?.getBoundingClientRect();
      return rect && rect.top >= 0 && rect.bottom <= innerHeight;
    },
    null,
    { timeout: 15000 },
  );
  const afterChange = await (await page.request.get(url + "api/state")).json();
  check(
    "Late common source history navigates HTML without a new document revision",
    beforeChange.revision === afterChange.revision && afterChange.changeToken,
  );
  const restoredY = await page.evaluate(() => scrollY);
  check("An unchanged editor cursor cannot replace shared restoration", !(await bridge.cursor()));
  assert.equal(await page.evaluate(() => scrollY), restoredY);
  await rpc("require('tinymist.reader').setup(_A)", {
    auto_open: false,
    root: sourceRoot,
    entry: sourcePath,
    change_file: changeFile,
  });
  await rpc("require('tinymist.reader').resume()");
  const expectedLine = original.slice(0, editStart).split("\n").length;
  for (
    let attempt = 0;
    (await rpc("require('tinymist.reader').cursor()")).line !== expectedLine;
    attempt++
  ) {
    assert.ok(attempt < 50, "Neovim did not restore the shared edit");
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  check("Neovim source restores the same saved edit as HTML", await bridge.cursor());
  const terminal = new TerminalReader({ ...options, protocol: "iterm2" }, page);
  const select = async (exact) => {
    // Real mouse drag, using rendered text range geometry rather than assigning Selection.
    const position = await page.evaluate((exact) => {
      const walker = document.createTreeWalker(
        document.querySelector("#reader-document"),
        NodeFilter.SHOW_TEXT,
      );
      let node;
      while ((node = walker.nextNode())) {
        const start = node.textContent.indexOf(exact);
        if (start < 0) continue;
        node.parentElement.scrollIntoView({ block: "center" });
        const range = document.createRange();
        range.setStart(node, start);
        range.setEnd(node, start + exact.length);
        const rects = [...range.getClientRects()];
        const first = rects[0],
          last = rects.at(-1);
        return {
          x: first.left + 0.2,
          y: first.top + first.height / 2,
          endX: last.right - 0.2,
          endY: last.top + last.height / 2,
        };
      }
      throw new Error(`Missing text: ${exact}`);
    }, exact);
    await page.mouse.move(position.x, position.y);
    await page.mouse.down();
    await page.mouse.move(position.endX, position.endY, { steps: 10 });
    await page.mouse.up();
    await page.waitForFunction(() => globalThis.flowReaderTerminal.selection()?.fragments.length);
    const selection = await page.evaluate(() => globalThis.flowReaderTerminal.selection());
    check(
      `Native DOM selection contains ${exact}`,
      selection.fragments
        .map((part) => part.exact)
        .join(" ")
        .includes(exact),
    );
    return selection;
  };
  const post = async (endpoint, payload) => {
    const response = await host.page.request.post(new URL(endpoint, url).href, { data: payload });
    assert.ok(response.ok(), await response.text());
    return response.json();
  };
  let selection = await select("selected ordinary passage");
  const location = await post("api/source", selection);
  check(
    `Reader selection maps to its saved source file: ${JSON.stringify(location)}`,
    location.status === "located" && location.path === (await realpath(entry)),
  );
  const followed = await post("api/cursor", {
    revision: selection.revision,
    path: entry,
    line: location.line,
    column: location.column,
  });
  check(
    "Source cursor maps back to the original Reader block",
    followed.status === "located" && followed.key === selection.fragments[0].key,
  );
  check(
    "Automatic follow preserves active selection",
    !(await page.evaluate((target) => globalThis.flowReaderTerminal.follow(target), followed)),
  );
  await bridge.source();
  check(
    "Terminal source action moves the real Neovim cursor",
    (await rpc("require('tinymist.reader').cursor()")).line === location.line,
  );
  await terminal.event({ type: "key", value: "s" });
  await page.waitForFunction(() => document.querySelector(".reader-review-marks span"));
  check("Strike leaves source unchanged", (await readFile(entry, "utf8")) === original);
  await page.waitForTimeout(2600);
  check("Terminal polling follows the real editor cursor", await bridge.cursor());
  await page.locator("#reader-menu").click();
  await page.waitForFunction(() => document.querySelector("#reader-navigation").open);
  // Let the ordinary gesture guard expire, so this tests the dialog itself
  // rather than a recent click or the earlier document selection.
  await page.waitForTimeout(2700);
  check(
    "An open native dialog alone prevents automatic follow and preserves reading position",
    await page.evaluate(async (target) => {
      const dialog = document.querySelector("#reader-navigation");
      const unselected = !getSelection()?.toString() && !globalThis.flowReaderTerminal.selection();
      const position = scrollY;
      const followed = await globalThis.flowReaderTerminal.follow(target);
      return unselected && dialog.open && !followed && scrollY === position;
    }, followed),
  );
  await page.keyboard.press("Escape");
  await page.waitForFunction(() => !document.querySelector("#reader-navigation").open);
  const staleFollow = { ...followed, revision: "an-old-document" };
  check(
    "A stale navigation result does not move the Reader",
    !(await page.evaluate((target) => globalThis.flowReaderTerminal.follow(target), staleFollow)),
  );
  await select("selected ordinary passage");
  const snapshot = path.join(repository, "dist/terminal-reader-check.png");
  await mkdir(path.dirname(snapshot), { recursive: true });
  await page.screenshot({ path: snapshot });
  const savedFocus = page.waitForResponse(
    (response) => response.url().endsWith("/api/focus") && response.request().method() === "POST",
  );
  check(
    "Save for Codex uses the shared HTML action",
    await page.evaluate(() => globalThis.flowReaderTerminal.action("save")),
  );
  check(
    "Save for Codex acknowledges through the shared HTML service",
    (await (await savedFocus).json()).status === "selected",
  );
  const beforeReopen = await (await page.request.get(url + "api/state")).json();
  await host.context.close();
  await reader.close();
  const disconnected = await (
    await fetch(url + "api/state", { signal: AbortSignal.timeout(5000) })
  ).json();
  check(
    "Closing the terminal leaves the accepted HTML service available",
    disconnected.revision === beforeReopen.revision,
  );
  reader = await startReader(options);
  options["editor-attachment"] = reader.editorAttachment;
  host = await openReader(options, { width: 760, height: 700 });
  await waitForReader(host.page, url, options);
  await host.page.waitForFunction(() => document.querySelector(".reader-review-marks span"));
  const afterReopen = await (await host.page.request.get(url + "api/state")).json();
  check(
    "Reopening the terminal preserves HTML service identity and does not compile",
    JSON.stringify(beforeReopen.service) === JSON.stringify(afterReopen.service) &&
      beforeReopen.compiledAt === afterReopen.compiledAt,
  );
  check(
    "Persistent terminal browser restores review strikes",
    await host.page.locator(".reader-review-marks span").count(),
  );
  check(
    "Terminal Save for Codex writes the shared server context",
    JSON.parse(await readFile(focusFile, "utf8")).selection?.text,
  );
  check(
    "Terminal Reader has no quotation library",
    (await host.page.locator("#reader-highlights-open, #reader-highlights").count()) === 0,
  );
  // Use the newly opened real page for the remaining edit checks.
  const current = host.page;
  current.on("pageerror", (error) => errors.push(error.message));
  const currentTerminal = new TerminalReader({ ...options, protocol: "iterm2" }, current);
  const selectCurrent = async () => {
    await current.evaluate(async () => {
      const { logicalTextIndex, rangesFor } = await import("./rendering/math/identity.js");
      const exact = "selected ordinary passage";
      const block = [...document.querySelectorAll("#reader-document [data-reader-key]")].find(
        (node) => logicalTextIndex(node).text.includes(exact),
      );
      const index = logicalTextIndex(block),
        start = index.text.indexOf(exact);
      const ranges = rangesFor(index, start, start + exact.length);
      const range = document.createRange();
      range.setStart(ranges[0].startContainer, ranges[0].startOffset);
      range.setEnd(ranges.at(-1).endContainer, ranges.at(-1).endOffset);
      getSelection().removeAllRanges();
      getSelection().addRange(range);
    });
    await current.waitForFunction(
      () => !document.querySelector("#reader-source-highlight").disabled,
    );
  };
  await rpc("vim.api.nvim_buf_set_lines(0, -1, -1, false, {'Unsaved editor work'})");
  await selectCurrent();
  const rejectedResponse = current.waitForResponse((response) =>
    response.url().endsWith("/api/highlight"),
  );
  await currentTerminal.event({ type: "key", value: "h" });
  const rejected = await (await rejectedResponse).json();
  check(
    "Terminal highlights assert the configured editor identity in the real HTTP request",
    (await rejectedResponse).request().postDataJSON().editorServer === address &&
      (await rejectedResponse).request().postDataJSON().editorAttachment ===
        reader.editorAttachment,
  );
  check(
    "Dirty Neovim buffer rejects the verified source highlight",
    rejected.status === "modified",
  );
  check(
    "Rejected highlight preserves disk and unsaved buffer",
    (await readFile(entry, "utf8")) === original && (await rpc("vim.bo.modified")),
  );
  await current.waitForFunction(() =>
    document.querySelector("#reader-highlight-message").textContent.includes("저장하지 않은"),
  );
  await rpc("(function() vim.cmd('edit!'); return true end)()");
  await selectCurrent();
  const acceptedResponse = current.waitForResponse((response) =>
    response.url().endsWith("/api/highlight"),
  );
  await currentTerminal.event({ type: "key", value: "h" });
  const accepted = await (await acceptedResponse).json();
  check(
    "Unmodified Neovim buffer accepts compiler-verified highlight",
    accepted.status === "highlighted",
  );
  const saved = await readFile(entry, "utf8");
  check(
    "Highlight updates disk and the real editor together",
    saved.includes("#highlighted[selected ordinary passage]") &&
      !(await rpc("vim.bo.modified")) &&
      (await rpc("table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\\n')")).includes(
        "#highlighted[selected ordinary passage]",
      ),
  );
  await current.waitForFunction(
    (old) => globalThis.flowReaderTerminal.state().revision !== old,
    selection.revision,
  );
  await selectCurrent();
  const markedSelection = await current.evaluate(() => globalThis.flowReaderTerminal.selection());
  const markedLocation = await post("api/source", markedSelection);
  check(
    "Source navigation survives a persisted source highlight",
    markedLocation.status === "located",
  );
  check("Browser bridge produced no page errors", errors.length === 0);
  await host.context.close();
  host = null;
  await reader.close();
  reader = null;
  await stop(editor);
  editor = null;
  const { stdout: viewReport } = await exec(
    process.env.PYTHON || "python3",
    [
      fileURLToPath(new URL("./neovim-browser-view.py", import.meta.url)),
      "--root",
      path.dirname(entry),
      "--entry",
      entry,
      "--address",
      address,
    ],
    { timeout: 60000 },
  );
  const view = JSON.parse(viewReport);
  check(
    "Same-connection Neovim TUI displays real Chromium SIXEL frames",
    view.started && view.sixelViewport.join("x") === "500x580",
  );
  check(
    "Internal Reader input, source cursor and quit restore the editor",
    view.input && view.source && view.stopped,
  );
  check("Dragging the Neovim divider resizes source and real Chromium frames", view.resized);
  console.log(`Terminal Reader: ${checks} integration checks passed. Snapshot: ${snapshot}`);
} finally {
  await host?.context.close().catch(() => {});
  await reader?.close();
  await stop(editor);
  await stop(fixture);
  lines.close();
  await rm(work, { recursive: true, force: true });
  if (priorPython === undefined) delete process.env.PYTHON;
  else process.env.PYTHON = priorPython;
  if (priorData === undefined) delete process.env.FLOW_READER_DATA_DIR;
  else process.env.FLOW_READER_DATA_DIR = priorData;
}
