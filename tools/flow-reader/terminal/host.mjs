// Translate native terminal input and publish current browser image frames.
import { createHash } from "node:crypto";
import { access } from "node:fs/promises";
import { once } from "node:events";
import {
  browserKey,
  graphicsProtocol,
  mousePosition,
  pngSequence,
  queryCellSize,
  statusSequence,
  terminalFinish,
  TerminalInput,
  terminalSize,
  terminalStart,
} from "./protocol.mjs";
import { EditorBridge } from "./editor-bridge.mjs";
import { readerControls } from "./options.mjs";
import { sixelSequence } from "./sixel.mjs";

export class TerminalReader {
  constructor(options, page) {
    this.options = options;
    this.page = page;
    this.protocol = options.protocol || graphicsProtocol();
    this.input = new TerminalInput();
    this.cellWidth = options["cell-width"] || 9;
    this.cellHeight = options["cell-height"] || 18;
    this.cellGeometryPriority = 0;
    this.isIterm = process.env.TERM_PROGRAM === "iTerm.app";
    this.size = terminalSize(
      process.stdout.columns,
      process.stdout.rows,
      this.cellWidth,
      this.cellHeight,
    );
    this.bridge = new EditorBridge(options, page);
    this.queue = Promise.resolve();
    this.mouseDown = false;
    this.message = readerControls;
    this.stopped = false;
    this.frameHash = "";
    this.frameGeneration = 0;
    this.clearBeforeFrame = false;
    this.outputAbort = new AbortController();
  }

  enqueue(action) {
    this.queue = this.queue.then(action).catch((error) => {
      this.message = error.message;
    });
  }

  async resize() {
    this.frameGeneration++;
    this.size = terminalSize(
      process.stdout.columns,
      process.stdout.rows,
      this.cellWidth,
      this.cellHeight,
    );
    await this.page.setViewportSize({ width: this.size.width, height: this.size.height });
    this.frameHash = "";
    this.clearBeforeFrame = true;
  }

  async event(event) {
    if (event.type === "paste") {
      await this.page.keyboard.insertText(event.value);
      return;
    }
    if (event.type === "geometry") {
      // iTerm2's CSI14t reports the entire OS window, including other panes.
      // Its OSC cell report is in logical points, matching browser CSS pixels;
      // multiplying by the Retina backing scale would make text too small.
      if (event.kind === 4 && this.isIterm) return;
      const priority = event.kind === "iterm" ? 3 : event.kind === 6 ? 2 : 1;
      if (priority < this.cellGeometryPriority) return;
      const width =
        this.options["cell-width"] ||
        (event.kind === 4 ? event.width / this.size.columns : event.width);
      const height =
        this.options["cell-height"] ||
        (event.kind === 4 ? event.height / this.size.rows : event.height);
      if (
        Number.isFinite(width) &&
        Number.isFinite(height) &&
        width > 0 &&
        height > 0 &&
        width <= 200 &&
        height <= 400
      ) {
        this.cellWidth = width;
        this.cellHeight = height;
        this.cellGeometryPriority = priority;
        await this.resize();
      }
      return;
    }
    if (event.type === "mouse") {
      const point = mousePosition(event, this.size);
      if (!point) {
        if (event.released && this.mouseDown) {
          await this.page.mouse.up();
          this.mouseDown = false;
        }
        return;
      }
      await this.page.mouse.move(point.x, point.y);
      if (event.button & 64) {
        await this.page.mouse.wheel(0, event.button & 1 ? 100 : -100);
      } else if (event.released) {
        if (this.mouseDown) await this.page.mouse.up();
        this.mouseDown = false;
      } else if (!(event.button & 32) && (event.button & 3) === 0 && !this.mouseDown) {
        await this.page.mouse.down();
        this.mouseDown = true;
      }
      return;
    }
    const value = event.value;
    if (value === "\x03" || value === "\x11") {
      this.stop();
      return;
    }
    const editable = await this.page.evaluate(() =>
      Boolean(
        document.activeElement?.matches(
          "input,textarea,[contenteditable='true'],[contenteditable='']",
        ),
      ),
    );
    if (!editable) {
      if (value === "q") {
        this.stop();
        return;
      }
      const action = { h: "highlight", s: "strike", u: "undo", X: "clear" }[value];
      if (action) {
        const accepted = await this.page.evaluate(
          (name) => window.flowReaderTerminal?.action(name),
          action,
        );
        this.message = accepted ? readerControls : "Select text to use that action";
        return;
      }
      if (value === "g") {
        await this.bridge.source();
        this.message = "Source cursor synchronized";
        return;
      }
      if (value === "j" || value === "k") {
        await this.page.mouse.wheel(0, value === "j" ? 80 : -80);
        return;
      }
      if (value === "?") {
        this.message = readerControls;
        return;
      }
    }
    const key = browserKey(value);
    if (key) await this.page.keyboard.press(key);
    else if (value.length && !value.startsWith("\x1b") && value.codePointAt(0) >= 32)
      await this.page.keyboard.insertText(value);
  }

  stop() {
    this.stopped = true;
    this.outputAbort.abort();
    this.resolveStop?.();
  }

  async run() {
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
    if (!this.protocol)
      throw new Error(
        "Use Windows Terminal with --protocol sixel, iTerm2 or a Kitty graphics terminal.",
      );
    const wasRaw = process.stdin.isRaw;
    const wasFlowing = process.stdin.readableFlowing;
    const stopPromise = new Promise((resolve) => {
      this.resolveStop = resolve;
    });
    let escapeTimer;
    const onData = (bytes) => {
      for (const event of this.input.read(bytes)) this.enqueue(() => this.event(event));
      clearTimeout(escapeTimer);
      escapeTimer = setTimeout(() => {
        for (const event of this.input.flushEscape()) this.enqueue(() => this.event(event));
      }, 40);
    };
    const onResize = () => {
      this.enqueue(() => this.resize());
      process.stdout.write(queryCellSize);
    };
    const onSignal = () => this.stop();
    const signals = ["SIGINT", "SIGTERM", "SIGHUP"];
    let captureBusy = false;
    let cursorBusy = false;
    let ownerBusy = false;
    const timers = [];
    try {
      // Finish the initial browser resize before enabling terminal replies.
      // Otherwise a fast cell report can finish its resize first, then be
      // overwritten by the slower initial viewport request.
      await this.resize();
      process.stdin.setRawMode(true);
      process.stdin.resume();
      process.stdin.on("data", onData);
      process.stdout.on("resize", onResize);
      for (const signal of signals) process.on(signal, onSignal);
      process.stdout.write(terminalStart + queryCellSize);
      const capture = async () => {
        if (captureBusy || this.stopped) return;
        captureBusy = true;
        // Screenshot backends can temporarily change/restore viewport metrics.
        // Serialize capture with resize and input so restoration cannot undo a
        // newer cell-size report or change the coordinates during a gesture.
        this.enqueue(async () => {
          try {
            if (this.stopped) return;
            const generation = this.frameGeneration;
            const png = await this.page.screenshot({ type: "png", scale: "css", timeout: 10000 });
            if (generation !== this.frameGeneration) return;
            const hash = createHash("sha256").update(png).digest("hex");
            if (!this.stopped && hash !== this.frameHash) {
              if (this.clearBeforeFrame) {
                process.stdout.write("\x1b[2J\x1b[H");
                this.clearBeforeFrame = false;
              }
              const frame =
                this.protocol === "sixel"
                  ? sixelSequence(png)
                  : pngSequence(png, this.size, this.protocol);
              if (!process.stdout.write(frame))
                await once(process.stdout, "drain", { signal: this.outputAbort.signal });
              this.frameHash = hash;
            }
            if (!this.stopped) process.stdout.write(statusSequence(this.message, this.size));
          } catch (error) {
            this.message = error.message;
          } finally {
            captureBusy = false;
          }
        });
        await this.queue;
      };
      timers.push(
        setInterval(capture, 1000 / (this.options.fps || (this.protocol === "sixel" ? 2 : 5))),
      );
      await capture();
      if (this.options["editor-server"] || this.options["sync-file"])
        timers.push(
          setInterval(async () => {
            if (cursorBusy || this.mouseDown || this.stopped) return;
            cursorBusy = true;
            try {
              await this.bridge.cursor();
            } catch (error) {
              this.message = error.message;
            } finally {
              cursorBusy = false;
            }
          }, 400),
        );
      if (this.options["parent-pid"] || this.options["control-file"])
        timers.push(
          setInterval(async () => {
            if (ownerBusy || this.stopped) return;
            ownerBusy = true;
            try {
              if (this.options["parent-pid"]) process.kill(this.options["parent-pid"], 0);
              if (this.options["control-file"]) await access(this.options["control-file"]);
            } catch {
              this.stop();
            } finally {
              ownerBusy = false;
            }
          }, 500),
        );
      await stopPromise;
    } finally {
      this.stop();
      for (const timer of timers) clearInterval(timer);
      clearTimeout(escapeTimer);
      process.stdin.off("data", onData);
      process.stdout.off("resize", onResize);
      for (const signal of signals) process.off(signal, onSignal);
      process.stdin.setRawMode(wasRaw);
      if (wasFlowing !== true) process.stdin.pause();
      process.stdout.write(terminalFinish);
      await this.queue;
    }
  }
}
