// Stable terminal options, document identity and persistent profile defaults.
import { createHash } from "node:crypto";
import { homedir } from "node:os";
import path from "node:path";

export const readerControls =
  "drag select · h highlight · s strike · u undo · X clear · g code · j/k scroll · q quit";

export const help = `tinymist-flow HTML Reader in a native terminal pane

node tools/flow-reader/terminal.mjs --url http://127.0.0.1:PORT/
node tools/flow-reader/terminal.mjs --root PROJECT --entry main.typ
node tools/flow-reader/terminal.mjs --session PATH --protocol sixel

Options:
  --url URL                 Existing stable Reader URL (HTTP or HTTPS)
  --root PATH               Resolve this project's managed HTML Reader
  --reader-service ID       Select an exact HTML Reader when matches are ambiguous
  --session PATH            Attach using an editor-owned argument manifest
  --embedded                Internal Neovim view transport (versioned JSON pipes)
  --entry PATH              Project-relative entrypoint (default main.typ)
  --profile PATH            Dedicated persistent Chromium profile
  --playwright-module PATH  Playwright module path (or FLOW_READER_PLAYWRIGHT_MODULE)
  --browser-executable PATH Chromium executable (otherwise installed Chrome)
  --protocol sixel|kitty|iterm2  Native image protocol (SIXEL for Windows Terminal)
  --cell-width NUMBER       Terminal cell width in pixels (otherwise queried)
  --cell-height NUMBER      Terminal cell height in pixels (otherwise queried)
  --fps NUMBER              Minimum capture interval, 1–20 (default 2 for SIXEL, otherwise 5)
  --metrics PATH            Append frame timing JSON Lines (or FLOW_READER_METRICS)
  --editor-server PATH      Neovim RPC server for code synchronization
  --nvim PATH               Neovim executable (default nvim)
  --parent-pid NUMBER       Exit when the owning editor exits
  --control-file PATH       Exit when the editor removes this launch file
  --sync-file PATH          Cursor JSON written by :FlowReader sync
  --check                   Print dependency/capability diagnosis and exit
  --snapshot PATH           Capture one real Reader PNG without requiring a terminal
  --help                    Show this help

Controls: drag to select; h source highlight; s strike; u undo strike;
X clear strikes; g selected text to code; j/k scroll; q quit. Tab/Enter and
mouse operate the actual HTML controls. Shortcuts pass through while typing.
Compiler, fonts, output, WASM and history settings come from the HTML Reader profile.
Closing the terminal view never stops the shared HTML Reader service.
Use Windows Terminal with SIXEL, iTerm2 or a Kitty graphics terminal outside tmux and
Neovim :terminal. Browser, local marks, and layout remain the real HTML Reader.
`;

export function parseArguments(argv) {
  const result = { fonts: [] };
  const flags = new Set(["check", "help", "embedded"]);
  const options = new Set([
    "url",
    "root",
    "reader-service",
    "session",
    "entry",
    "package-path",
    "compiler",
    "engine",
    "font-path",
    "output",
    "port",
    "original-url",
    "profile",
    "playwright-module",
    "browser-executable",
    "protocol",
    "cell-width",
    "cell-height",
    "fps",
    "metrics",
    "editor-server",
    "nvim",
    "parent-pid",
    "control-file",
    "sync-file",
    "change-file",
    "snapshot",
  ]);
  for (let index = 0; index < argv.length; index++) {
    const key = argv[index].replace(/^--/, "");
    if (!argv[index].startsWith("--") || (!flags.has(key) && !options.has(key)))
      throw new Error(`Unknown option: ${argv[index]}`);
    if (flags.has(key)) result[key] = true;
    else {
      const value = argv[++index];
      if (!value || value.startsWith("--")) throw new Error(`Missing value for --${key}`);
      if (key === "font-path") result.fonts.push(value);
      else result[key] = value;
    }
  }
  if (result.url && result.root) throw new Error("Use either --url or --root");
  if (result.url) {
    const url = new URL(result.url);
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password)
      throw new Error("Reader URL must use HTTP(S) without embedded credentials");
    result.url = url.href;
  }
  for (const [key, minimum, maximum] of [
    ["port", 1, 65535],
    ["cell-width", 1, 200],
    ["cell-height", 1, 400],
    ["fps", 1, 20],
    ["parent-pid", 1, Number.MAX_SAFE_INTEGER],
  ]) {
    if (result[key] !== undefined) {
      const number = Number(result[key]);
      if (
        !Number.isFinite(number) ||
        number < minimum ||
        number > maximum ||
        ((key === "port" || key === "parent-pid") && !Number.isInteger(number))
      )
        throw new Error(`Invalid --${key}: ${result[key]}`);
      result[key] = number;
    }
  }
  if (result.protocol && !["iterm2", "kitty", "sixel"].includes(result.protocol))
    throw new Error("--protocol must be sixel, kitty or iterm2");
  return result;
}

export function projectIdentity(options) {
  return options.url ?? `${path.resolve(options.root ?? ".")}\0${options.entry ?? "main.typ"}`;
}

export function profileDefaults(options) {
  const digest = createHash("sha256").update(projectIdentity(options)).digest();
  const base =
    process.platform === "darwin"
      ? path.join(homedir(), "Library", "Application Support", "tinymist-flow", "terminal")
      : path.join(
          process.env.XDG_DATA_HOME || path.join(homedir(), ".local", "share"),
          "tinymist-flow",
          "terminal",
        );
  const directory = path.join(base, digest.toString("hex").slice(0, 20));
  return {
    profile: path.join(directory, "chromium"),
  };
}
