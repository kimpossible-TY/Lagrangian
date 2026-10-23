import { SnapshotCompiler } from "./runtime.js";

let compiler;
let busy = false;
globalThis.onmessage = async ({ data }) => {
  if (busy) {
    globalThis.postMessage({ id: data.id, error: "Compiler is busy" });
    return;
  }
  busy = true;
  try {
    if (data.type === "init") {
      const started = performance.now();
      const moduleURL = new URL(data.moduleURL, globalThis.location.href);
      const wasmURL = new URL(data.wasmURL, moduleURL);
      if (moduleURL.origin !== globalThis.location.origin || wasmURL.origin !== moduleURL.origin)
        throw new Error("Compiler assets must belong to the Reader origin");
      const module = await import(moduleURL.href);
      await module.default({ module_or_path: wasmURL.href });
      compiler?.dispose();
      compiler = new SnapshotCompiler(module, data.engine);
      globalThis.postMessage({
        id: data.id,
        ready: true,
        initMs: performance.now() - started,
        wasmMemoryBytes: module.memory_bytes(),
      });
    } else if (data.type === "compile") {
      if (!compiler) throw new Error("Compiler is not initialized");
      const result = await compiler.compile(data.snapshot);
      globalThis.postMessage({ id: data.id, ...result }, [result.artifact.buffer]);
    } else {
      throw new Error("Unknown compiler operation");
    }
  } catch (error) {
    compiler?.dispose();
    compiler = null;
    globalThis.postMessage({ id: data.id, error: String(error) });
  } finally {
    busy = false;
  }
};
