// Full native-terminal ownership; browser behavior stays in TerminalReader.
import { once } from "node:events";
import {
  TerminalInput,
  queryCellSize,
  terminalStart,
  terminalFinish,
  statusSequence,
} from "./protocol.mjs";

export class NativeTransport {
  dimensions() {
    return [process.stdout.columns, process.stdout.rows];
  }

  async open(reader) {
    if (!process.stdin.isTTY || !process.stdout.isTTY)
      throw new Error(
        "A native terminal pane is required. Use --check or --snapshot for noninteractive validation.",
      );
    if (process.env.TMUX)
      throw new Error(
        "Run the Reader in a native terminal split outside tmux; image placement inside tmux is not supported.",
      );
    if (process.env.NVIM)
      throw new Error("Run the Reader in a native terminal split, outside Neovim :terminal.");
    if (!reader.protocol)
      throw new Error(
        "Use Windows Terminal with --protocol sixel, iTerm2 or a Kitty graphics terminal.",
      );
    const input = new TerminalInput();
    const wasRaw = process.stdin.isRaw;
    const wasFlowing = process.stdin.readableFlowing;
    let escapeTimer;
    const onData = (bytes) => {
      for (const event of input.read(bytes)) reader.enqueue(() => reader.event(event));
      clearTimeout(escapeTimer);
      escapeTimer = setTimeout(() => {
        for (const event of input.flushEscape()) reader.enqueue(() => reader.event(event));
      }, 40);
    };
    const onResize = () => {
      reader.enqueue(() => reader.resize());
      process.stdout.write(queryCellSize);
    };
    const onSignal = () => reader.stop();
    const signals = ["SIGINT", "SIGTERM", "SIGHUP"];
    await reader.resize();
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.on("data", onData);
    process.stdout.on("resize", onResize);
    for (const signal of signals) process.on(signal, onSignal);
    process.stdout.write(terminalStart + queryCellSize);
    return () => {
      clearTimeout(escapeTimer);
      process.stdin.off("data", onData);
      process.stdout.off("resize", onResize);
      for (const signal of signals) process.off(signal, onSignal);
      process.stdin.setRawMode(wasRaw);
      if (wasFlowing !== true) process.stdin.pause();
      process.stdout.write(terminalFinish);
    };
  }

  async present(frame, signal) {
    if (frame.image) {
      if (frame.clear) process.stdout.write("\x1b[2J\x1b[H");
      if (!process.stdout.write(frame.image)) await once(process.stdout, "drain", { signal });
    }
    if (!signal.aborted) process.stdout.write(statusSequence(frame.status, frame.size));
  }
}
