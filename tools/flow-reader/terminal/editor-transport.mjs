// Versioned, bounded editor job pipes. The editor owns positioning and TUI modes.
import { TerminalInput } from "./protocol.mjs";

export function editorLayout(message) {
  if (message?.type !== "resize" || typeof message.visible !== "boolean")
    throw new Error("Invalid editor Reader layout");
  for (const [key, min, max] of [
    ["generation", 1, Number.MAX_SAFE_INTEGER],
    ["columns", 1, 2000],
    ["rows", 2, 1000],
    ["cellWidth", 1, 200],
    ["cellHeight", 1, 400],
  ]) {
    if (
      !Number.isFinite(message[key]) ||
      message[key] < min ||
      message[key] > max ||
      (!key.startsWith("cell") && !Number.isInteger(message[key]))
    )
      throw new Error(`Invalid editor Reader ${key}`);
  }
  const width = Math.round(message.columns * message.cellWidth);
  const height = Math.round((message.rows - 1) * message.cellHeight);
  if (width > 32768 || height > 32768 || width * height > 16777216)
    throw new Error("Editor Reader viewport exceeds the frame limit");
  return message;
}

export class EditorTransport {
  constructor(input = process.stdin, output = process.stdout) {
    this.input = input;
    this.output = output;
    this.sequence = 0;
  }

  dimensions() {
    return [80, 24];
  }

  async open(reader) {
    const decoder = new TerminalInput();
    let pending = "";
    let escapeTimer;
    let initialized = false;
    let ready;
    const firstLayout = new Promise((resolve) => {
      ready = resolve;
    });
    const fail = (error) => {
      this.output.write(
        JSON.stringify({ version: 1, type: "error", message: error.message }) + "\n",
      );
      reader.stop();
      ready();
    };
    const onEnd = () => {
      reader.stop();
      ready();
    };
    const onData = (data) => {
      pending += data.toString("utf8");
      if (Buffer.byteLength(pending) > 1048576)
        return fail(new Error("Editor Reader input exceeds the message limit"));
      let end;
      while ((end = pending.indexOf("\n")) >= 0) {
        const line = pending.slice(0, end);
        pending = pending.slice(end + 1);
        try {
          const message = JSON.parse(line);
          if (message.version !== 1) throw new Error("Unsupported editor Reader protocol");
          if (message.type === "ack") {
            if (message.id === this.sequence) this.ack?.();
          } else if (message.type === "stop") onEnd();
          else if (message.type === "resize") {
            const layout = editorLayout(message);
            if (layout.generation <= (this.generation || 0)) continue;
            this.generation = layout.generation;
            reader.enqueue(() => reader.resize(layout)).then(ready);
            initialized = true;
          } else if (message.type === "input" && initialized && typeof message.data === "string") {
            for (const event of decoder.read(Buffer.from(message.data)))
              if (event.type !== "geometry") reader.enqueue(() => reader.event(event));
            clearTimeout(escapeTimer);
            escapeTimer = setTimeout(() => {
              for (const event of decoder.flushEscape()) reader.enqueue(() => reader.event(event));
            }, 40);
          } else throw new Error("Unexpected editor Reader message");
        } catch (error) {
          fail(error);
          return;
        }
      }
    };
    this.input.setEncoding("utf8");
    const wasFlowing = this.input.readableFlowing;
    this.input.on("data", onData);
    this.input.on("end", onEnd);
    this.input.on("error", onEnd);
    this.output.on("error", onEnd);
    this.input.resume();
    if (this.input.readableEnded || this.input.destroyed) onEnd();
    const onAbort = () => {
      this.ack?.();
      ready();
    };
    reader.outputAbort.signal.addEventListener("abort", onAbort);
    this.output.write(JSON.stringify({ version: 1, type: "ready" }) + "\n");
    const timeout = setTimeout(
      () => fail(new Error("Editor Reader layout was not received")),
      10000,
    );
    await firstLayout;
    clearTimeout(timeout);
    return () => {
      clearTimeout(escapeTimer);
      this.input.off("data", onData);
      this.input.off("end", onEnd);
      this.input.off("error", onEnd);
      this.output.off("error", onEnd);
      if (wasFlowing !== true) this.input.pause();
      reader.outputAbort.signal.removeEventListener("abort", onAbort);
    };
  }

  async present(frame, signal) {
    if (signal.aborted) return;
    const message = {
      version: 1,
      type: "frame",
      id: ++this.sequence,
      generation: frame.generation,
      columns: frame.size.columns,
      rows: frame.size.imageRows,
      status: frame.status,
      image: frame.image,
    };
    // One outstanding frame bounds memory and network traffic even on a slow TUI.
    await new Promise((resolve) => {
      this.ack = resolve;
      this.output.write(JSON.stringify(message) + "\n");
    });
    this.ack = null;
  }
}
