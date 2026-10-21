// Own browser interaction, capture ordering and editor/service lifetime.
// Concrete transports own terminal modes or the editor's framed stdio channel.
import { createHash } from "node:crypto";
import { access } from "node:fs/promises";
import {
  browserKey,
  graphicsProtocol,
  mousePosition,
  pngSequence,
  terminalSize,
} from "./protocol.mjs";
import { EditorBridge } from "./editor-bridge.mjs";
import { readerControls } from "./options.mjs";
import { sixelSequence } from "./sixel.mjs";
import { NativeTransport } from "./native-transport.mjs";

export class TerminalReader {
  constructor(options, page, transport = new NativeTransport()) {
    this.options = options;
    this.page = page;
    this.transport = transport;
    this.protocol = options.protocol || graphicsProtocol();
    this.cellWidth = options["cell-width"] || 9;
    this.cellHeight = options["cell-height"] || 18;
    this.cellGeometryPriority = 0;
    this.isIterm = process.env.TERM_PROGRAM === "iTerm.app";
    this.size = terminalSize(...transport.dimensions(), this.cellWidth, this.cellHeight);
    this.bridge = new EditorBridge(options, page);
    this.queue = Promise.resolve();
    this.mouseDown = false;
    this.message = readerControls;
    this.stopped = false;
    this.visible = true;
    this.frameHash = "";
    this.frameGeneration = 0;
    this.layoutGeneration = 0;
    this.clearBeforeFrame = false;
    this.outputAbort = new AbortController();
  }

  enqueue(action) {
    this.queue = this.queue
      .then(async () => {
        if (!this.stopped) await action();
      })
      .catch((error) => {
        if (!this.stopped) this.message = error.message;
      });
    return this.queue;
  }

  async resize(layout) {
    this.frameGeneration++;
    if (layout) {
      this.cellWidth = layout.cellWidth;
      this.cellHeight = layout.cellHeight;
      this.layoutGeneration = layout.generation;
      this.visible = layout.visible;
    }
    this.size = terminalSize(
      ...(layout ? [layout.columns, layout.rows] : this.transport.dimensions()),
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

  async capture() {
    if (this.captureBusy || this.stopped || !this.visible) return;
    this.captureBusy = true;
    try {
      let captured;
      await this.enqueue(async () => {
        const generation = this.frameGeneration;
        const png = await this.page.screenshot({ type: "png", scale: "css", timeout: 10000 });
        if (this.stopped || generation !== this.frameGeneration) return;
        const hash = createHash("sha256").update(png).digest("hex");
        const image =
          hash === this.frameHash
            ? null
            : this.protocol === "sixel"
              ? sixelSequence(png)
              : pngSequence(png, this.size, this.protocol);
        captured = {
          hash,
          frameGeneration: generation,
          frame: {
            image,
            size: this.size,
            status: this.message,
            generation: this.layoutGeneration,
            clear: this.clearBeforeFrame,
          },
        };
      });
      // Slow presentation must not block browser input, resize or cancellation.
      if (captured && !this.stopped) {
        await this.transport.present(captured.frame, this.outputAbort.signal);
        if (captured.frameGeneration === this.frameGeneration) {
          this.clearBeforeFrame = false;
          this.frameHash = captured.hash;
        }
      }
    } catch (error) {
      if (!this.stopped) this.message = error.message;
    } finally {
      this.captureBusy = false;
    }
  }

  async run() {
    const stopPromise = new Promise((resolve) => {
      this.resolveStop = resolve;
    });
    const timers = [];
    let close;
    let cursorBusy = false;
    let ownerBusy = false;
    try {
      close = await this.transport.open(this);
      if (this.stopped) return;
      timers.push(
        setInterval(
          () => this.capture(),
          1000 / (this.options.fps || (this.protocol === "sixel" ? 2 : 5)),
        ),
      );
      await this.capture();
      if (this.options["editor-server"] || this.options["sync-file"])
        timers.push(
          setInterval(async () => {
            if (cursorBusy || this.mouseDown || this.stopped || !this.visible) return;
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
      await close?.();
      await this.queue;
    }
  }
}
