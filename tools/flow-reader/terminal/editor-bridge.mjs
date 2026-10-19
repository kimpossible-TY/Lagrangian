// Bridge explicit saved-source navigation to the configured Neovim owner.
import { execFile } from "node:child_process";
import { readFile, stat } from "node:fs/promises";
import { promisify } from "node:util";
const runFile = promisify(execFile);

function vimString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

export class EditorBridge {
  constructor(options, page) {
    this.options = options;
    this.page = page;
    this.lastCursor = "";
    this.lastSync = 0;
  }

  async rpc(expression) {
    const { stdout } = await runFile(
      this.options.nvim || "nvim",
      ["--server", this.options["editor-server"], "--remote-expr", expression],
      { timeout: 2500, maxBuffer: 1024 * 1024 },
    );
    return JSON.parse(stdout);
  }

  async cursor() {
    let forced = false;
    let cursor;
    if (this.options["sync-file"]) {
      const info = await stat(this.options["sync-file"]).catch(() => null);
      if (info && info.mtimeMs > this.lastSync) {
        this.lastSync = info.mtimeMs;
        cursor = JSON.parse(await readFile(this.options["sync-file"], "utf8"));
        forced = true;
      }
    }
    if (!cursor && this.options["editor-server"])
      cursor = await this.rpc(`luaeval("vim.json.encode(require('tinymist.reader').cursor())")`);
    if (!cursor || cursor.modified) return false;
    const identity = JSON.stringify(cursor);
    if (!forced && identity === this.lastCursor) return false;
    const selection = await this.page.evaluate(() => Boolean(window.getSelection()?.toString()));
    if (selection && !forced) return false;
    const state = await (
      await this.page.request.get(new URL("api/state", this.page.url()).href)
    ).json();
    if (!state.revision) return false;
    const response = await this.page.request.post(new URL("api/cursor", this.page.url()).href, {
      data: { revision: state.revision, ...cursor },
    });
    if (!response.ok()) return false;
    const location = await response.json();
    if (location.status !== "located") return false;
    const followed = await this.page.evaluate(
      async (location) => Boolean(await window.flowReaderTerminal?.follow(location)),
      location,
    );
    if (followed) this.lastCursor = identity;
    return followed;
  }

  async source() {
    if (!this.options["editor-server"]) throw new Error("Source navigation needs --editor-server");
    const selection = await this.page.evaluate(() => window.flowReaderTerminal?.selection());
    if (!selection?.fragments?.length) throw new Error("Select a passage before pressing g");
    const response = await this.page.request.post(new URL("api/source", this.page.url()).href, {
      data: selection,
    });
    const location = await response.json();
    if (!response.ok() || location.status !== "located")
      throw new Error(location.error || "Source location is ambiguous");
    const result = await this.rpc(
      `json_encode(luaeval("require('tinymist.reader').jump(_A)", json_decode(${vimString(JSON.stringify(location))})))`,
    );
    if (result === "modified")
      throw new Error(
        "Neovim has unsaved changes in the target buffer. Save it before source navigation.",
      );
    if (result === "stale")
      throw new Error(
        "Source changed before Neovim could navigate. Refresh the Reader and select again.",
      );
    if (result !== "jumped")
      throw new Error("Source navigation failed in Neovim; no cursor was moved.");
    return result;
  }
}
