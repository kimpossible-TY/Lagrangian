// Attach presentation to the HTML service manager; never own a compiler/service.
import { execFile } from "node:child_process";
import { unlink } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
const runFile = promisify(execFile);
const manager = fileURLToPath(new URL("../manage.py", import.meta.url));

export function attachmentArguments(options) {
  if (!options.root) throw new Error("Specify --url or the managed HTML Reader's --root");
  if (
    options.fonts?.length ||
    ["compiler", "engine", "package-path", "output", "port", "original-url", "change-file"].some(
      (key) => options[key] !== undefined,
    )
  )
    throw new Error(
      "Compiler, font, output and history settings belong to the managed HTML Reader profile, not the terminal host.",
    );
  const args = [
    manager,
    "--attach",
    "--root",
    path.resolve(options.root),
    "--entry",
    options.entry || "main.typ",
  ];
  for (const key of ["reader-service", "editor-server", "nvim", "control-file"])
    if (options[key]) args.push(`--${key}`, options[key]);
  if (options["editor-server"]) args.push("--owner-pid", String(process.pid));
  return args;
}

export async function startReader(options) {
  if (options.url) return { url: options.url, close: async () => {} };
  let plan;
  try {
    const { stdout } = await runFile(
      process.env.PYTHON || "python3",
      attachmentArguments(options),
      {
        timeout: 30000,
        maxBuffer: 1024 * 1024,
        env: { ...process.env, PYTHONDONTWRITEBYTECODE: "1" },
      },
    );
    plan = JSON.parse(stdout);
  } catch (error) {
    throw new Error(
      `Could not attach to the managed HTML Reader: ${error.stderr?.trim() || error.message}`,
    );
  }
  let closed = false;
  return {
    ...plan,
    async close() {
      if (closed) return;
      closed = true;
      if (plan.attachmentFile)
        await unlink(plan.attachmentFile).catch((error) => {
          if (error.code !== "ENOENT") throw error;
        });
    },
  };
}
