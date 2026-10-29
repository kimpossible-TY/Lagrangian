import { spawnSync } from "node:child_process";
import { copyFile } from "node:fs/promises";
import { resolve } from "node:path";

// Preview HTML and runtime translations are gitignored sources. `include_str!`
// needs both of them before `tinymist` can compile with preview and l10n.
const root = resolve(import.meta.dirname, "..");
const result = spawnSync(process.execPath, ["scripts/build.mjs", "build:preview"], {
  cwd: root,
  stdio: "inherit",
});
if (result.status !== 0) {
  process.exit(result.status === null ? 1 : result.status);
}

await copyFile(
  resolve(root, "locales/tinymist-rt.toml"),
  resolve(root, "crates/tinymist-assets/src/tinymist-rt.toml"),
);
