import { afterEach, describe, expect, it, vi } from "vitest";
import { PreviewConnection } from "./preview-connection";

class TestSocket extends EventTarget {
  readyState = 0;
  binaryType: BinaryType = "blob";
  send = vi.fn();
  close = vi.fn(() => {
    this.readyState = 3;
    this.dispatchEvent(new Event("close"));
  });
  open() {
    this.readyState = 1;
    this.dispatchEvent(new Event("open"));
  }
  message() {
    this.dispatchEvent(new MessageEvent("message", { data: new ArrayBuffer(1) }));
  }
}

function viewer(hidden = false, online = true) {
  vi.useFakeTimers();
  const page = Object.assign(new EventTarget(), { hidden });
  const lifecycle = new EventTarget();
  const sockets: TestSocket[] = [];
  const callbacks = { opened: vi.fn(), message: vi.fn(), disconnected: vi.fn() };
  const connection = new PreviewConnection(
    "ws://preview",
    callbacks,
    page,
    lifecycle,
    () => {
      const socket = new TestSocket();
      sockets.push(socket);
      return socket;
    },
    { onLine: online },
  );
  const visibility = (hidden: boolean) => {
    page.hidden = hidden;
    page.dispatchEvent(new Event("visibilitychange"));
  };
  return { connection, sockets, callbacks, visibility, lifecycle };
}

afterEach(() => vi.useRealTimers());

describe("suspended preview connections", () => {
  it("reuses a healthy socket and probes only on return", () => {
    const v = viewer();
    v.sockets[0].open();
    v.connection.supportPing();
    vi.advanceTimersByTime(60000);
    expect(v.sockets[0].send).not.toHaveBeenCalled();
    v.visibility(true);
    vi.advanceTimersByTime(60000);
    v.visibility(false);
    v.lifecycle.dispatchEvent(new Event("pageshow"));
    expect(v.sockets[0].send).toHaveBeenCalledExactlyOnceWith("ping");
    v.sockets[0].message();
    vi.advanceTimersByTime(60000);
    expect(v.sockets).toHaveLength(1);
    expect(v.sockets[0].close).not.toHaveBeenCalled();
    v.connection.dispose();
  });

  it("does not send unsupported probes to an older engine", () => {
    const v = viewer();
    v.sockets[0].open();
    v.visibility(true);
    v.visibility(false);
    vi.advanceTimersByTime(60000);
    expect(v.sockets[0].send).not.toHaveBeenCalled();
    expect(v.sockets).toHaveLength(1);
    v.connection.dispose();
  });

  it("defers retries while hidden and reconnects immediately when visible", () => {
    const v = viewer();
    v.sockets[0].open();
    v.visibility(true);
    v.sockets[0].close();
    vi.advanceTimersByTime(60000);
    expect(v.sockets).toHaveLength(1);
    v.visibility(false);
    expect(v.sockets).toHaveLength(2);
    v.connection.dispose();
  });

  it("cancels an existing retry and does not create competing sockets", () => {
    const v = viewer();
    v.sockets[0].close();
    v.visibility(true);
    v.visibility(false);
    v.lifecycle.dispatchEvent(new Event("online"));
    v.lifecycle.dispatchEvent(new Event("pageshow"));
    v.sockets[1].open();
    vi.advanceTimersByTime(60000);
    expect(v.sockets).toHaveLength(2);
    v.connection.dispose();
  });

  it("replaces a socket that looks open but cannot answer a foreground probe", () => {
    const v = viewer();
    v.sockets[0].open();
    v.connection.supportPing();
    v.visibility(true);
    v.visibility(false);
    vi.advanceTimersByTime(2999);
    expect(v.sockets).toHaveLength(1);
    vi.advanceTimersByTime(1);
    expect(v.sockets).toHaveLength(2);
    expect(v.callbacks.disconnected).toHaveBeenCalledOnce();
    v.sockets[0].message();
    v.sockets[0].dispatchEvent(new Event("error"));
    expect(v.callbacks.message).not.toHaveBeenCalled();
    expect(v.callbacks.disconnected).toHaveBeenCalledOnce();
    v.connection.dispose();
  });

  it("suspends a probe deadline when the viewer leaves again", () => {
    const v = viewer();
    v.sockets[0].open();
    v.connection.supportPing();
    v.visibility(true);
    v.visibility(false);
    v.visibility(true);
    vi.advanceTimersByTime(60000);
    expect(v.sockets).toHaveLength(1);
    v.visibility(false);
    v.sockets[0].message();
    vi.advanceTimersByTime(60000);
    expect(v.sockets).toHaveLength(1);
    v.connection.dispose();
  });

  it("bounds a stalled opening handshake and backs off failures", () => {
    const v = viewer();
    vi.advanceTimersByTime(10000);
    expect(v.callbacks.disconnected).toHaveBeenCalledOnce();
    vi.advanceTimersByTime(1000);
    expect(v.sockets).toHaveLength(2);
    v.sockets[1].dispatchEvent(new Event("error"));
    vi.advanceTimersByTime(1999);
    expect(v.sockets).toHaveLength(2);
    vi.advanceTimersByTime(1);
    expect(v.sockets).toHaveLength(3);
    v.connection.dispose();
  });

  it("handles bfcache return and cleans up all callbacks on disposal", () => {
    const v = viewer();
    v.sockets[0].open();
    v.lifecycle.dispatchEvent(new Event("pagehide"));
    v.sockets[0].close();
    v.lifecycle.dispatchEvent(new Event("pageshow"));
    expect(v.sockets).toHaveLength(2);
    v.connection.dispose();
    v.visibility(false);
    v.lifecycle.dispatchEvent(new Event("online"));
    v.sockets[1].open();
    v.sockets[1].message();
    vi.advanceTimersByTime(60000);
    expect(v.sockets).toHaveLength(2);
    expect(v.callbacks.opened).toHaveBeenCalledOnce();
    expect(v.callbacks.message).not.toHaveBeenCalled();
    expect(vi.getTimerCount()).toBe(0);
  });

  it("waits for visibility on an initially hidden page", () => {
    const v = viewer(true);
    vi.advanceTimersByTime(60000);
    expect(v.sockets).toHaveLength(0);
    v.visibility(false);
    expect(v.sockets).toHaveLength(1);
    v.connection.dispose();
  });

  it("makes no initial or retry network requests while known offline", () => {
    const v = viewer(false, false);
    vi.advanceTimersByTime(60000);
    v.lifecycle.dispatchEvent(new Event("pageshow"));
    expect(v.sockets).toHaveLength(0);
    v.lifecycle.dispatchEvent(new Event("online"));
    expect(v.sockets).toHaveLength(1);
    v.sockets[0].close();
    v.lifecycle.dispatchEvent(new Event("offline"));
    vi.advanceTimersByTime(60000);
    expect(v.sockets).toHaveLength(1);
    v.lifecycle.dispatchEvent(new Event("online"));
    expect(v.sockets).toHaveLength(2);
    v.connection.dispose();
  });

  it("suspends a foreground probe offline and probes the retained socket on return", () => {
    const v = viewer();
    v.sockets[0].open();
    v.connection.supportPing();
    v.lifecycle.dispatchEvent(new Event("pageshow"));
    v.lifecycle.dispatchEvent(new Event("offline"));
    vi.advanceTimersByTime(60000);
    expect(v.sockets[0].close).not.toHaveBeenCalled();
    v.lifecycle.dispatchEvent(new Event("online"));
    expect(v.sockets[0].send).toHaveBeenCalledTimes(2);
    v.sockets[0].message();
    vi.advanceTimersByTime(60000);
    expect(v.sockets).toHaveLength(1);
    v.connection.dispose();
    v.lifecycle.dispatchEvent(new Event("offline"));
    v.lifecycle.dispatchEvent(new Event("online"));
    expect(vi.getTimerCount()).toBe(0);
  });

  it("replaces an older engine's open socket after actual offline recovery without probing it", () => {
    const v = viewer();
    v.sockets[0].open();
    v.lifecycle.dispatchEvent(new Event("offline"));
    v.lifecycle.dispatchEvent(new Event("online"));
    expect(v.sockets[0].send).not.toHaveBeenCalled();
    expect(v.sockets[0].close).toHaveBeenCalledOnce();
    expect(v.sockets).toHaveLength(2);
    v.connection.dispose();
  });
});
