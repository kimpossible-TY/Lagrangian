/** Snapshot-only WASM compilation. Python remains the publication authority. */
const MAX_BYTES = 128 * 1024 * 1024;

async function decode(file) {
  if (typeof file.data !== "string" || file.data.length > Math.ceil(MAX_BYTES / 3) * 4)
    throw new Error("Invalid compiler input size");
  const bytes = Uint8Array.from(atob(file.data), (character) => character.charCodeAt(0));
  const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
  if (hash !== file.sha256) throw new Error("Compiler input hash mismatch");
  return bytes;
}

export class SnapshotCompiler {
  constructor(module, engine, progress = () => {}) {
    Object.assign(this, { module, engine, progress });
    this.files = new Map();
    this.compiler = null;
    this.fonts = null;
    this.runs = 0;
  }

  async compile(snapshot) {
    if (
      snapshot.schemaVersion !== 1 ||
      snapshot.engine !== this.engine ||
      !["html", "pdf"].includes(snapshot.target) ||
      !Number.isSafeInteger(snapshot.timestamp) ||
      !Array.isArray(snapshot.files) ||
      !Array.isArray(snapshot.fonts) ||
      snapshot.files.length + snapshot.fonts.length > 8192
    )
      throw new Error("Unsupported compiler snapshot");
    const started = performance.now();
    let bytes = 0;
    for (const file of [...snapshot.files, ...snapshot.fonts]) {
      if (typeof file.data !== "string") throw new Error("Missing compiler input bytes");
      bytes += (file.data.length * 3) / 4;
      if (bytes > MAX_BYTES) throw new Error("Compiler input byte limit exceeded");
    }
    this.progress({ phase: "fonts", wasmMemoryBytes: this.module.memory_bytes() });
    const fonts = JSON.stringify(snapshot.fonts.map((file) => [file.path, file.sha256]));
    if (fonts !== this.fonts) {
      this.compiler?.free();
      this.compiler = new this.module.BrowserCompiler();
      this.files.clear();
      this.fonts = null;
      for (const font of snapshot.fonts) this.compiler.add_font(await decode(font));
      this.fonts = fonts;
    }
    this.progress({ phase: "files", wasmMemoryBytes: this.module.memory_bytes() });
    const wanted = new Set();
    for (const file of snapshot.files) {
      if (typeof file.path !== "string" || wanted.has(file.path))
        throw new Error("Duplicate or invalid compiler input path");
      wanted.add(file.path);
      if (this.files.get(file.path) === file.sha256) continue;
      this.compiler.set_file(file.path, await decode(file));
      this.files.set(file.path, file.sha256);
    }
    for (const path of this.files.keys()) {
      if (!wanted.has(path)) {
        this.compiler.remove_file(path);
        this.files.delete(path);
      }
    }
    const prepared = performance.now();
    this.progress({ phase: "evaluating", wasmMemoryBytes: this.module.memory_bytes() });
    const result = this.compiler.compile(
      snapshot.entry,
      snapshot.target,
      JSON.stringify(snapshot.inputs),
      BigInt(snapshot.timestamp),
    );
    try {
      this.progress({ phase: "output", wasmMemoryBytes: this.module.memory_bytes() });
      return {
        identity: snapshot.identity,
        returncode: result.ok() ? 0 : 1,
        stderr: result.diagnostics(),
        artifact: result.artifact(),
        dependencies: JSON.parse(result.dependencies()),
        metrics: {
          prepareMs: prepared - started,
          compileMs: performance.now() - prepared,
          wasmMemoryBytes: this.module.memory_bytes(),
          run: ++this.runs,
        },
      };
    } finally {
      result.free();
    }
  }

  dispose() {
    this.compiler?.free();
    this.compiler = null;
    this.fonts = null;
    this.files.clear();
  }
}
