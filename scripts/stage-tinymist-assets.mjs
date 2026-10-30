// Stage the gitignored sources that `tinymist-assets` embeds with `include_str!`.
//
// Invocation, from the repository root:
//   node scripts/stage-tinymist-assets.mjs
//
// The working directory does not matter. Paths are resolved from this file.
// Run `yarn install --frozen-lockfile` first. The preview build shells out to
// `npx tsc` and `npx vite build`.
//
// Arguments:
//   None. An extra argument exits 2. This does not run `yarn build:l10n` and
//   does not compile Rust. Localization is a copy of the committed catalog, so
//   a later release-profile engine build is not preceded by another Rust profile.
//
// Outputs, relative to the repository root:
//   crates/tinymist-assets/src/typst-preview.html
//     Preview page from `node scripts/build.mjs build:preview`
//     (`tools/typst-preview-frontend/dist/index.html`).
//   crates/tinymist-assets/src/tinymist-rt.toml
//     Copy of `locales/tinymist-rt.toml`.
//
// Exit status:
//   0  Both outputs exist and are non-empty. The preview build inherits
//      stdout and stderr. This script writes nothing on success.
//   1  The preview build could not be spawned, the copy failed, or either
//      output is missing or empty.
//   2  Arguments were supplied.
//   N  The preview build exited N, when N is not 0.

import { spawnSync } from "node:child_process";
import { copyFile, stat } from "node:fs/promises";
import { resolve } from "node:path";

if (process.argv.length > 2) {
  console.error("usage: node scripts/stage-tinymist-assets.mjs");
  process.exit(2);
}

const root = resolve(import.meta.dirname, "..");
const previewHtml = resolve(root, "crates/tinymist-assets/src/typst-preview.html");
const l10nSource = resolve(root, "locales/tinymist-rt.toml");
const l10nToml = resolve(root, "crates/tinymist-assets/src/tinymist-rt.toml");

const preview = spawnSync(process.execPath, ["scripts/build.mjs", "build:preview"], {
  cwd: root,
  stdio: "inherit",
});
if (preview.status === null) {
  process.exit(1);
}
if (preview.status !== 0) {
  process.exit(preview.status);
}

try {
  await copyFile(l10nSource, l10nToml);
  for (const output of [previewHtml, l10nToml]) {
    const info = await stat(output);
    if (!info.isFile() || info.size === 0) {
      throw new Error(`missing or empty asset: ${output}`);
    }
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
