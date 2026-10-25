// Opt-in frame timing records. Never write to stdout or an interactive display.
import { createWriteStream } from "node:fs";

export class FrameMetrics {
  constructor(destination = null) {
    this.destination = destination;
  }

  record(entry) {
    if (!this.destination) return;
    const line = JSON.stringify({ time: new Date().toISOString(), ...entry }) + "\n";
    if (this.destination === process.stderr) {
      process.stderr.write(line);
      return;
    }
    if (!this.destination.destroyed) this.destination.write(line);
  }

  close() {
    if (!this.destination || this.destination === process.stderr) return Promise.resolve();
    return new Promise((resolve) => this.destination.end(resolve));
  }
}

export function frameMetrics(options = {}, environment = process.env) {
  const configured = options.metrics ?? environment.FLOW_READER_METRICS;
  if (!configured) return new FrameMetrics();
  if (configured === "-" || configured === "stderr") {
    // stderr shares the terminal with a native Reader; JSON Lines would corrupt it.
    if (process.stderr.isTTY)
      throw new Error("--metrics stderr would corrupt the Reader display; use a file path");
    return new FrameMetrics(process.stderr);
  }
  const stream = createWriteStream(configured, { flags: "a" });
  stream.on("error", () => {
    stream.destroy();
  });
  return new FrameMetrics(stream);
}
