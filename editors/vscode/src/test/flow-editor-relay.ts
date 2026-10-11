import type { Server } from "node:http";
import { WebSocket, WebSocketServer } from "ws";

/** A small engine relay fixture; real origin and isolation checks live in flow-app. */
export function attachFlowEditorRelay(server: Server) {
  const sockets = new WebSocketServer({ noServer: true });
  const sessions = new Map<string, { host: WebSocket; viewers: Set<WebSocket> }>();
  server.on("upgrade", (request, socket, head) => {
    const route = new URL(request.url!, "http://localhost").pathname;
    const match = /^\/(editor|_editor)\/([a-f0-9-]{36})$/.exec(route);
    if (!match || (match[1] === "_editor" && request.headers.origin)) {
      socket.end("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n");
      return;
    }
    const [, role, channel] = match;
    if (
      (role === "_editor" && sessions.has(channel)) ||
      (role === "editor" && !sessions.has(channel))
    ) {
      socket.end("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
      return;
    }
    sockets.handleUpgrade(request, socket, head, (connection) => {
      sockets.emit("connection", connection, request);
      if (role === "_editor") {
        const session = { host: connection, viewers: new Set<WebSocket>() };
        sessions.set(channel, session);
        connection.send(Buffer.from(JSON.stringify({ event: "editorReady" })));
        connection.on("message", (bytes) => {
          for (const viewer of session.viewers) viewer.send(bytes, { binary: true });
        });
        connection.on("close", () => {
          for (const viewer of session.viewers) viewer.close();
          sessions.delete(channel);
        });
      } else {
        const session = sessions.get(channel)!;
        session.viewers.add(connection);
        const notify = () =>
          session.host.send(
            Buffer.from(
              JSON.stringify({
                event: "editorConnected",
                connected: session.viewers.size > 0,
              }),
            ),
          );
        notify();
        connection.on("message", (bytes) => session.host.send(bytes, { binary: true }));
        connection.on("close", () => {
          session.viewers.delete(connection);
          if (session.host.readyState === WebSocket.OPEN) notify();
        });
      }
      connection.on("error", () => {});
    });
  });
  return {
    dispose() {
      for (const socket of sockets.clients) socket.terminate();
      sockets.close();
    },
  };
}
