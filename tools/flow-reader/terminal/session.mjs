// Read a private editor-owned invocation without launching a shell or executable.
import { readFile } from "node:fs/promises";
import path from "node:path";
import { parseArguments } from "./options.mjs";

export async function sessionOptions(options) {
  if (!options.session) return options;
  const overrides = new Set([
    "session",
    "protocol",
    "fps",
    "cell-width",
    "cell-height",
    "check",
    "help",
  ]);
  if (
    options.fonts.length ||
    Object.keys(options).some((key) => key !== "fonts" && !overrides.has(key))
  )
    throw new Error("--session accepts only protocol, fps, cell-size, --check or --help overrides");
  const record = JSON.parse(await readFile(options.session, "utf8"));
  if (
    !record ||
    record.version !== 1 ||
    !Array.isArray(record.args) ||
    record.args.some((arg) => typeof arg !== "string" || arg.includes("\0") || arg === "--session")
  )
    throw new Error("Invalid editor Reader session manifest");
  const saved = parseArguments(record.args);
  if (
    !saved["editor-server"] ||
    !saved["parent-pid"] ||
    !saved["control-file"] ||
    path.resolve(saved["control-file"]) !== path.resolve(options.session) ||
    (!saved.root && !saved.url) ||
    saved.check ||
    saved.help ||
    saved.snapshot
  )
    throw new Error("Reader session must retain its editor, document and lifecycle control file");
  try {
    process.kill(saved["parent-pid"], 0);
  } catch {
    throw new Error("The editor owning this Reader session is no longer running");
  }
  const result = { ...saved };
  for (const key of overrides)
    if (key !== "session" && options[key] !== undefined) result[key] = options[key];
  return result;
}
