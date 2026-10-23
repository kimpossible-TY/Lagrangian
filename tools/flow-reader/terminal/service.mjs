// Start and stop only the Reader service owned by this terminal launch.
import { spawn, execFile } from "node:child_process";
import path from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { profileDefaults } from "./options.mjs";
const runFile = promisify(execFile);
const HERE = fileURLToPath(new URL("../", import.meta.url));

export function serverArguments(options) {
  const defaults = profileDefaults(options);
  const args = [
    path.join(HERE, "serve.py"),
    "--root",
    path.resolve(options.root),
    "--entry",
    options.entry || "main.typ",
    "--package-path",
    path.resolve(options["package-path"] || path.join(HERE, "packages")),
    "--compiler",
    options.compiler || "typst",
    "--output",
    path.resolve(options.output || defaults.output),
    "--port",
    String(options.port || defaults.port),
    "--original-url",
    options["original-url"] || `http://127.0.0.1:${options.port || defaults.port}/`,
    "--watch",
  ];
  for (const font of options.fonts || []) args.push("--font-path", font);
  if (options["editor-server"]) args.push("--editor-server", options["editor-server"]);
  if (options.nvim) args.push("--nvim", options.nvim);
  if (options["change-file"]) args.push("--change-file", options["change-file"]);
  return args;
}

export async function startReader(options) {
  if (options.url) return { url: options.url, close: async () => {} };
  if (!options.root) throw new Error("Specify --url or --root");
  const processHandle = spawn(process.env.PYTHON || "python3", serverArguments(options), {
    stdio: ["ignore", "pipe", "pipe"],
    // A separate POSIX group lets close() stop compiler descendants as well.
    detached: process.platform !== "win32",
  });
  const lines = createInterface({ input: processHandle.stdout });
  let errors = "";
  processHandle.stderr.on("data", (chunk) => {
    errors = (errors + chunk).slice(-12000);
  });
  let closing;
  const close = () => {
    if (closing) return closing;
    closing = (async () => {
      lines.close();
      if (!processHandle.pid) return;
      if (process.platform === "win32") {
        if (processHandle.exitCode !== null || processHandle.signalCode !== null) return;
        try {
          await runFile("taskkill", ["/PID", String(processHandle.pid), "/T", "/F"], {
            timeout: 5000,
          });
        } catch {
          processHandle.kill("SIGKILL");
        }
        return;
      }
      const signalGroup = (signal) => {
        try {
          process.kill(-processHandle.pid, signal);
          return true;
        } catch (error) {
          if (error.code !== "ESRCH") throw error;
          return false;
        }
      };
      const exited =
        processHandle.exitCode !== null || processHandle.signalCode !== null
          ? Promise.resolve()
          : new Promise((resolve) => processHandle.once("exit", resolve));
      if (!signalGroup("SIGTERM")) return;
      let timer;
      try {
        await Promise.race([
          exited,
          new Promise((resolve) => {
            timer = setTimeout(resolve, 3000);
          }),
        ]);
      } finally {
        clearTimeout(timer);
        // The Python parent may exit before a compiler which ignores SIGTERM.
        signalGroup("SIGKILL");
      }
    })();
    return closing;
  };

  try {
    const url = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`Reader did not start. ${errors}`)), 15000);
      const fail = (error) => {
        clearTimeout(timer);
        reject(error);
      };
      processHandle.once("error", fail);
      processHandle.once("exit", (code) =>
        fail(
          new Error(`Reader exited (${code}). The stable port may already be in use. ${errors}`),
        ),
      );
      lines.once("line", (line) => {
        clearTimeout(timer);
        try {
          resolve(JSON.parse(line).url);
        } catch {
          fail(new Error(`Invalid Reader startup response: ${line}`));
        }
      });
    });
    return { url, close, process: processHandle, errors: () => errors };
  } catch (error) {
    await close();
    throw error;
  }
}
