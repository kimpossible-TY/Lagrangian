type Socket = Pick<WebSocket, "readyState" | "binaryType" | "send" | "close" | "addEventListener">;

/** Recover suspended viewers without closing a healthy socket or polling in the background. */
export class PreviewConnection {
  private socket?: Socket;
  private timer?: ReturnType<typeof setTimeout>;
  private probing = false;
  private pingSupported = false;
  private paused = false;
  private disposed = false;
  private failures = 0;
  private visibility = () => (this.page.hidden ? this.pause() : this.resume());
  private hide = () => this.pause();
  private show = () => this.resume();

  constructor(
    private url: string,
    private callbacks: {
      opened: (socket: Socket) => void;
      message: (data: ArrayBuffer, socket: Socket) => void;
      disconnected: () => void;
    },
    private page: Pick<Document, "hidden" | "addEventListener" | "removeEventListener"> = document,
    private lifecycle: Pick<Window, "addEventListener" | "removeEventListener"> = window,
    private createSocket: (url: string) => Socket = (url) => new WebSocket(url),
  ) {
    this.paused = page.hidden;
    page.addEventListener("visibilitychange", this.visibility);
    lifecycle.addEventListener("pagehide", this.hide);
    lifecycle.addEventListener("pageshow", this.show);
    lifecycle.addEventListener("online", this.show);
    if (!this.paused) this.connect();
  }

  supportPing() {
    this.pingSupported = true;
  }

  private clearTimer() {
    clearTimeout(this.timer);
    this.timer = undefined;
    this.probing = false;
  }

  private pause() {
    this.paused = true;
    this.clearTimer();
  }

  private resume() {
    if (this.disposed || this.page.hidden) return;
    this.paused = false;
    const socket = this.socket;
    if (!socket) {
      this.clearTimer();
      this.connect();
    } else if (socket.readyState === 1) {
      if (!this.pingSupported || this.probing) return;
      // Only upgraded servers accept this application-level ping. A probe is
      // sent once on foreground entry, never on a periodic background timer.
      this.probing = true;
      this.timer = setTimeout(() => this.fail(socket, true), 3000);
      try {
        socket.send("ping");
      } catch {
        this.fail(socket, true);
      }
    } else if (socket.readyState === 0) {
      if (this.timer === undefined) this.watchOpening(socket);
    } else {
      this.fail(socket, true);
    }
  }

  private watchOpening(socket: Socket) {
    this.timer = setTimeout(() => this.fail(socket), 10000);
  }

  private connect() {
    if (this.disposed || this.paused || this.socket) return;
    this.clearTimer();
    let socket: Socket;
    try {
      socket = this.createSocket(this.url);
    } catch {
      this.callbacks.disconnected();
      this.retry();
      return;
    }
    this.socket = socket;
    socket.binaryType = "arraybuffer";
    this.pingSupported = false;
    this.watchOpening(socket);
    const current = () => !this.disposed && this.socket === socket;
    socket.addEventListener("open", () => {
      if (!current()) return;
      this.clearTimer();
      this.failures = 0;
      this.callbacks.opened(socket);
    });
    socket.addEventListener("message", (event) => {
      if (!current()) return;
      if (this.probing) this.clearTimer();
      this.callbacks.message((event as MessageEvent).data, socket);
    });
    socket.addEventListener("close", () => {
      if (current()) this.fail(socket);
    });
    socket.addEventListener("error", () => {
      if (current()) this.fail(socket);
    });
  }

  private fail(socket: Socket, immediate = false) {
    if (this.disposed || this.socket !== socket) return;
    this.socket = undefined;
    this.clearTimer();
    try {
      socket.close();
    } catch {
      // Some browsers reject close() while the handshake is still pending.
    }
    this.callbacks.disconnected();
    if (immediate && !this.paused) this.connect();
    else this.retry();
  }

  private retry() {
    if (this.disposed || this.paused) return;
    const delay = Math.min(1000 * 2 ** this.failures++, 10000);
    this.timer = setTimeout(() => this.connect(), delay);
  }

  dispose() {
    this.disposed = true;
    this.clearTimer();
    this.page.removeEventListener("visibilitychange", this.visibility);
    this.lifecycle.removeEventListener("pagehide", this.hide);
    this.lifecycle.removeEventListener("pageshow", this.show);
    this.lifecycle.removeEventListener("online", this.show);
    try {
      this.socket?.close();
    } catch {
      // Disposal also covers an unfinished browser handshake.
    }
    this.socket = undefined;
  }
}
