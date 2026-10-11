import * as ws from "ws";
import { l10nMsg } from "../l10n";
import type { PreviewSourceJump } from "./preview-sync";

export interface PanelScrollRequest {
  event: "panelScrollTo";
  filepath: string;
  line: number;
  character: number;
}

export interface BrowserEditorBridge {
  readonly connected: boolean;
  send(request: PanelScrollRequest): boolean;
  dispose(): void;
}

/** Only small upstream control messages traverse the engine's same-port relay. */
export async function createBrowserEditorBridge(
  localReaderUrl: string,
  channel: string,
  reveal: (value: PreviewSourceJump) => Promise<void>,
): Promise<BrowserEditorBridge> {
  // Namespace imports keep the desktop-only client out of the web runtime path.
  const { WebSocket } = ws;
  const endpoint = new URL(`/_editor/${channel}`, localReaderUrl);
  if (endpoint.protocol !== "http:" || endpoint.hostname !== "127.0.0.1") {
    throw new Error("The Flow editor host must connect over loopback.");
  }
  endpoint.protocol = "ws:";
  let socket: ws.WebSocket | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let disposed = false;
  let connected = false;
  let ready = false;
  let busy = false;
  let failures = 0;
  let initialResolve!: () => void;
  let initialReject!: (error: Error) => void;
  const initial = new Promise<void>((resolve, reject) => {
    initialResolve = resolve;
    initialReject = reject;
  });
  const initialTimeout = setTimeout(() => {
    initialReject(
      new Error(l10nMsg("The Flow engine could not establish editor synchronization.")),
    );
  }, 3000);
  const connect = () => {
    if (disposed) return;
    const current = new WebSocket(endpoint, { maxPayload: 8192, handshakeTimeout: 3000 });
    socket = current;
    current.on("error", () => {});
    current.on("close", () => {
      if (disposed || socket !== current) return;
      connected = false;
      socket = undefined;
      if (!ready) {
        initialReject(
          new Error(l10nMsg("Update tinymist-flow to use shared editor synchronization.")),
        );
        return;
      }
      timer = setTimeout(connect, Math.min(1000 * 2 ** failures++, 10000));
    });
    current.on("message", async (raw) => {
      if (disposed || socket !== current) return;
      let value: unknown;
      try {
        const bytes = Array.isArray(raw)
          ? Buffer.concat(raw)
          : Buffer.isBuffer(raw)
            ? raw
            : Buffer.from(raw);
        value = JSON.parse(bytes.toString("utf8"));
      } catch {
        return;
      }
      const event = value as { event?: unknown; connected?: unknown } | null;
      if (event?.event === "editorReady") {
        ready = true;
        failures = 0;
        clearTimeout(initialTimeout);
        initialResolve();
      } else if (event?.event === "editorConnected") {
        connected = event.connected === true;
      } else if (event?.event === "editorScrollTo" && !busy) {
        busy = true;
        try {
          await reveal(value as PreviewSourceJump);
        } catch {
          // Source failures must not expose paths or interrupt the shared service.
        } finally {
          busy = false;
        }
      }
    });
  };
  const bridge: BrowserEditorBridge = {
    get connected() {
      return !disposed && connected && socket?.readyState === WebSocket.OPEN;
    },
    send(request) {
      if (!bridge.connected || !socket || socket.bufferedAmount > 8192) return false;
      const payload = JSON.stringify(request);
      if (Buffer.byteLength(payload) > 8192) return false;
      socket.send(payload);
      return true;
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      connected = false;
      clearTimeout(initialTimeout);
      clearTimeout(timer);
      socket?.terminate();
      socket = undefined;
    },
  };
  connect();
  try {
    await initial;
    return bridge;
  } catch (error) {
    bridge.dispose();
    throw error;
  }
}
