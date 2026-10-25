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
import { frameMetrics } from "./metrics.mjs";
import { readerControls } from "./options.mjs";
import { startScreencastSignals } from "./screencast.mjs";
import { sixelSequence } from "./sixel.mjs";
import { NativeTransport } from "./native-transport.mjs";

// Frame metrics are diagnostic; keep sub-millisecond encoding visible.
function elapsed(start) {
  return Math.round((performance.now() - start) * 100) / 100;
}

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
    this.ready = false;
    this.visible = true;
    this.frameHash = "";
    this.frameGeneration = 0;
    this.layoutGeneration = 0;
    this.clearBeforeFrame = false;
    this.outputAbort = new AbortController();
    this.metrics = frameMetrics(options);
    this.frameCount = 0;
    this.unchangedTotal = 0;
    this.captureInterval = 1000 / (options.fps || (this.protocol === "sixel" ? 2 : 5));
    this.captureBusy = false;
    this.capturePending = false;
    this.captureTimer = null;
    this.lastCaptureAt = 0;
    this.stopWatching = null;
  }

  enqueue(action) {
    this.queue = this.queue
      .then(async () => {
        if (!this.stopped) await action();
      })
      .catch((error) => {
        if (!this.stopped) this.setMessage(error.message);
      });
    return this.queue;
  }

  setMessage(message) {
    if (this.message === message) return;
    this.message = message;
    // The statusline is part of a frame even when browser pixels do not change.
    this.requestCapture();
  }

  requestCapture() {
    if (this.stopped || !this.ready) return;
    this.capturePending = true;
    this.armCapture();
  }

  armCapture() {
    if (
      this.stopped ||
      !this.ready ||
      !this.capturePending ||
      this.captureBusy ||
      this.captureTimer
    )
      return;
    // fps is the minimum spacing between captures, not a polling period.
    const wait = Math.max(0, this.lastCaptureAt + this.captureInterval - Date.now());
    this.captureTimer = setTimeout(() => {
      this.captureTimer = null;
      this.capture().finally(() => {
        if (this.capturePending) this.armCapture();
      });
    }, wait);
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
    this.requestCapture();
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
        this.setMessage(accepted ? readerControls : "Select text to use that action");
        return;
      }
      if (value === "g") {
        await this.bridge.source();
        this.setMessage("Source cursor synchronized");
        return;
      }
      if (value === "j" || value === "k") {
        await this.page.mouse.wheel(0, value === "j" ? 80 : -80);
        return;
      }
      if (value === "?") {
        this.setMessage(readerControls);
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
    clearTimeout(this.captureTimer);
    this.captureTimer = null;
    this.outputAbort.abort();
    this.resolveStop?.();
  }

  async capture() {
    if (this.stopped) return;
    if (!this.visible) {
      this.capturePending = false;
      return;
    }
    if (this.captureBusy) {
      this.capturePending = true;
      return;
    }
    this.captureBusy = true;
    this.capturePending = false;
    this.lastCaptureAt = Date.now();
    const metric = { type: "frame", frame: ++this.frameCount, protocol: this.protocol };
    try {
      let captured;
      await this.enqueue(async () => {
        const generation = this.frameGeneration;
        const screenshotStart = performance.now();
        const png = await this.page.screenshot({ type: "png", scale: "css", timeout: 10000 });
        const screenshotMs = elapsed(screenshotStart);
        if (this.stopped) return;
        if (generation !== this.frameGeneration) {
          captured = { discarded: "generation", screenshotMs };
          return;
        }
        const hash = createHash("sha256").update(png).digest("hex");
        const unchanged = hash === this.frameHash;
        if (unchanged) this.unchangedTotal++;
        let image = null;
        let encodeMs = 0;
        if (!unchanged) {
          const encodeStart = performance.now();
          image =
            this.protocol === "sixel"
              ? sixelSequence(png)
              : pngSequence(png, this.size, this.protocol);
          encodeMs = elapsed(encodeStart);
        }
        captured = {
          hash,
          frameGeneration: generation,
          screenshotMs,
          encodeMs,
          unchanged,
          frame: {
            image,
            // SIXEL output remains unchanged until its synchronized-update
            // behavior is verified in a physical Windows Terminal.
            sync: this.protocol !== "sixel",
            size: this.size,
            status: this.message,
            generation: this.layoutGeneration,
            clear: this.clearBeforeFrame,
          },
        };
      });
      // Slow presentation must not block browser input, resize or cancellation.
      if (!captured) {
        metric.discarded = this.stopped ? "stopped" : "queue";
      } else if (captured.discarded) {
        Object.assign(metric, captured);
      } else if (!this.stopped) {
        metric.screenshotMs = captured.screenshotMs;
        metric.encodeMs = captured.encodeMs;
        metric.unchanged = captured.unchanged;
        const presentStart = performance.now();
        metric.bytes = Number(
          (await this.transport.present(captured.frame, this.outputAbort.signal)) || 0,
        );
        metric.presentMs = elapsed(presentStart);
        if (captured.frameGeneration === this.frameGeneration) {
          this.clearBeforeFrame = false;
          this.frameHash = captured.hash;
        }
      }
    } catch (error) {
      if (!this.stopped) this.setMessage(error.message);
    } finally {
      this.captureBusy = false;
      metric.unchangedTotal = this.unchangedTotal;
      this.metrics.record(metric);
      if (this.capturePending && !this.stopped) this.armCapture();
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
      this.ready = true;
      // Browser changes are the capture signal; fps only bounds their frequency.
      this.stopWatching = await startScreencastSignals(this.page, () => this.requestCapture());
      await this.capture();
      if (this.options["editor-server"] || this.options["sync-file"])
        timers.push(
          setInterval(async () => {
            if (cursorBusy || this.mouseDown || this.stopped || !this.visible) return;
            cursorBusy = true;
            try {
              await this.bridge.cursor();
            } catch (error) {
              this.setMessage(error.message);
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
      await this.stopWatching?.();
      this.stopWatching = null;
      await close?.();
      await this.queue;
      await this.metrics.close();
    }
  }
}
