// Compose a shared HTML attachment, browser, input host and owned-view cleanup.
import { access, open, unlink } from "node:fs/promises";
import path from "node:path";
import { parseArguments, help } from "./options.mjs";
import { graphicsProtocol, terminalSize } from "./protocol.mjs";
import { loadPlaywright, browserOptions, openReader, waitForReader } from "./browser-session.mjs";
import { startReader } from "./service.mjs";
import { TerminalReader } from "./host.mjs";
import { EditorTransport } from "./editor-transport.mjs";
import { sessionOptions } from "./session.mjs";

async function runMain(options) {
  if (options.help) {
    process.stdout.write(help);
    return;
  }
  if (options.embedded && (!options.protocol || options.snapshot || options.check))
    throw new Error("--embedded requires an explicit protocol and an interactive editor view");
  if (options.check) {
    const report = {
      node: process.version,
      tty: Boolean(process.stdin.isTTY && process.stdout.isTTY),
      protocol: options.protocol || graphicsProtocol(),
      tmux: Boolean(process.env.TMUX),
      nvimTerminal: Boolean(process.env.NVIM),
    };
    try {
      const { chromium } = await loadPlaywright(options);
      const browser = await chromium.launch({ ...(await browserOptions(options)), headless: true });
      report.browser = browser.version();
      await browser.close();
      report.ready = Boolean(report.tty && report.protocol && !report.tmux && !report.nvimTerminal);
    } catch (error) {
      report.error = error.message;
      process.exitCode = 1;
    }
    process.stdout.write(JSON.stringify(report, null, 2) + "\n");
    return;
  }
  if (!options.snapshot && !options.embedded) {
    if (!process.stdin.isTTY || !process.stdout.isTTY)
      throw new Error(
        "A native terminal pane is required; use --check or --snapshot for validation.",
      );
    if (process.env.TMUX || process.env.NVIM)
      throw new Error(
        "Open the Reader in a native terminal split outside tmux and Neovim :terminal.",
      );
    if (!(options.protocol || graphicsProtocol()))
      throw new Error(
        "A graphics terminal is required: use Windows Terminal with --protocol sixel, iTerm2 or a Kitty graphics terminal.",
      );
  }
  let reader;
  let browser;
  let terminal;
  let interrupted = false;
  const onSignal = () => {
    interrupted = true;
    if (terminal) terminal.stop();
    else {
      browser?.context.close().catch(() => {});
      reader?.close().catch(() => {});
    }
  };
  const signals = ["SIGINT", "SIGTERM", "SIGHUP"];
  for (const signal of signals) process.on(signal, onSignal);
  let checkingOwner = false;
  const ownerTimer =
    options["parent-pid"] || options["control-file"]
      ? setInterval(async () => {
          if (checkingOwner || interrupted) return;
          checkingOwner = true;
          try {
            if (options["parent-pid"]) process.kill(options["parent-pid"], 0);
            if (options["control-file"]) await access(options["control-file"]);
          } catch {
            onSignal();
          } finally {
            checkingOwner = false;
          }
        }, 500)
      : null;
  try {
    reader = await startReader(options);
    options = { ...options, "editor-attachment": reader.editorAttachment };
    if (interrupted) {
      return;
    }
    const size = terminalSize(
      options.snapshot ? 100 : process.stdout.columns,
      options.snapshot ? 40 : process.stdout.rows,
      options["cell-width"] || 9,
      options["cell-height"] || 18,
    );
    browser = await openReader(options, { width: size.width, height: size.height });
    if (interrupted) {
      return;
    }
    await waitForReader(browser.page, reader.url, options);
    if (options.snapshot) {
      await browser.page.screenshot({ path: path.resolve(options.snapshot), type: "png" });
      process.stdout.write(
        JSON.stringify({
          url: reader.url,
          snapshot: path.resolve(options.snapshot),
          viewport: { width: size.width, height: size.height },
        }) + "\n",
      );
    } else {
      terminal = new TerminalReader(
        options,
        browser.page,
        options.embedded ? new EditorTransport() : undefined,
      );
      await terminal.run();
    }
  } finally {
    clearInterval(ownerTimer);
    for (const signal of signals) process.off(signal, onSignal);
    try {
      await browser?.context.close();
    } finally {
      await reader?.close();
    }
  }
}

export async function main(argv = process.argv.slice(2)) {
  let options;
  let attachment;
  try {
    const requested = parseArguments(argv);
    const resolved = await sessionOptions(requested);
    if (requested.session && !resolved.check && !resolved.help) {
      const lock = `${requested.session}.attached`;
      try {
        const handle = await open(lock, "wx", 0o600);
        attachment = { lock, handle };
      } catch (error) {
        if (error.code === "EEXIST")
          throw new Error(
            "This Reader session is already attached; stop it in Neovim before restarting",
          );
        throw error;
      }
    }
    options = resolved;
    await runMain(options);
  } finally {
    const index = argv.indexOf("--control-file");
    const control =
      options?.["control-file"] ||
      (!argv.includes("--session") && index >= 0 ? argv[index + 1] : null);
    if (control && !control.startsWith("--") && !options?.check && !options?.help)
      await unlink(control).catch(() => {});
    if (attachment) {
      await attachment.handle.close();
      await unlink(attachment.lock).catch(() => {});
    }
  }
}
