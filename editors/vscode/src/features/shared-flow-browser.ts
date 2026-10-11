import * as http from "node:http";
import type { AddressInfo } from "node:net";
import * as ws from "ws";
import type { PreviewSourceJump } from "./preview-sync";

export interface PanelScrollRequest {
  event: "panelScrollTo";
  filepath: string;
  line: number;
  character: number;
}

export interface BrowserEditorBridge {
  localUrl: string;
  readonly connected: boolean;
  send(request: PanelScrollRequest): boolean;
  dispose(): void;
}

/** The upstream control protocol, with no document frames or memory-file events. */
export async function createBrowserEditorBridge(
  readerOrigin: string,
  channel: string,
  reveal: (value: PreviewSourceJump) => Promise<void>,
): Promise<BrowserEditorBridge> {
  const route = `/editor/${channel}`;
  // Namespace imports keep desktop-only servers out of the web runtime path.
  const { createServer } = http;
  const { WebSocketServer } = ws;
  const server = createServer((_request, response) => response.writeHead(404).end());
  const sockets = new WebSocketServer({ noServer: true, maxPayload: 8192 });
  server.on("upgrade", (request, socket, head) => {
    if (
      new URL(request.url || "/", "http://localhost").pathname !== route ||
      request.headers.origin !== readerOrigin
    ) {
      socket.end("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n");
      return;
    }
    sockets.handleUpgrade(request, socket, head, (connection) => {
      sockets.emit("connection", connection, request);
    });
  });
  sockets.on("connection", (connection) => {
    let busy = false;
    connection.on("error", () => {});
    connection.on("message", async (raw, binary) => {
      if (binary || busy) return;
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
      if ((value as { event?: unknown } | null)?.event !== "editorScrollTo") return;
      busy = true;
      try {
        await reveal(value as PreviewSourceJump);
      } catch {
        // A failed source reveal must not expose local paths or tear down Flow.
      } finally {
        busy = false;
      }
    });
  });
  server.headersTimeout = 5000;
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  let disposed = false;
  return {
    localUrl: `http://127.0.0.1:${(server.address() as AddressInfo).port}${route}`,
    get connected() {
      return (
        !disposed && Array.from(sockets.clients).some((c) => c.readyState === ws.WebSocket.OPEN)
      );
    },
    send(request) {
      if (disposed) return false;
      const payload = Buffer.from(JSON.stringify(request));
      if (payload.byteLength > 8192) return false;
      let sent = false;
      for (const connection of sockets.clients) {
        if (connection.readyState !== ws.WebSocket.OPEN) continue;
        // Slow/disconnected readers must not accumulate cursor movement events.
        if (connection.bufferedAmount > 8192) continue;
        connection.send(payload);
        sent = true;
      }
      return sent;
    },
    dispose() {
      disposed = true;
      for (const connection of sockets.clients) connection.terminate();
      sockets.close();
      server.closeAllConnections();
      server.close();
    },
  };
}
