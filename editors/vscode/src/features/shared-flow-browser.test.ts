import { once } from "node:events";
import { expect, test, vi } from "vitest";
import { WebSocket } from "ws";
import { createBrowserEditorBridge } from "./shared-flow-browser";

const origin = "http://localhost:23625";
const jump = { event: "editorScrollTo", filepath: "/project/main.typ", start: [2, 3], end: [2, 8] };

test("shared control protocol is bidirectional, origin/session checked, and disposed independently", async () => {
  const reveal = vi.fn().mockResolvedValue(undefined);
  const bridge = await createBrowserEditorBridge(origin, "unique-session", reveal);
  const sockets: WebSocket[] = [];
  const url = bridge.localUrl.replace(/^http/, "ws");
  try {
    for (const [endpoint, readerOrigin] of [
      [url, "https://other.example"],
      [url.replace("unique-session", "other"), origin],
    ]) {
      const denied = new WebSocket(endpoint, { origin: readerOrigin });
      sockets.push(denied);
      const error = new Promise<Error>((resolve) => denied.once("error", resolve));
      expect((await error).message).toContain("403");
    }
    const connection = new WebSocket(url + "?forwarding=preserved", { origin });
    sockets.push(connection);
    await once(connection, "open");
    connection.send(JSON.stringify({ event: "syncMemoryFiles", files: {} }));
    connection.send("bad json");
    connection.send(JSON.stringify(jump));
    await vi.waitFor(() => expect(reveal).toHaveBeenCalledExactlyOnceWith(jump));
    const response = once(connection, "message");
    expect(
      bridge.send({ event: "panelScrollTo", filepath: jump.filepath, line: 2, character: 4 }),
    ).toBe(true);
    const [payload] = (await response) as [Buffer];
    expect(JSON.parse(payload.toString())).toEqual({
      event: "panelScrollTo",
      filepath: jump.filepath,
      line: 2,
      character: 4,
    });
    const closed = once(connection, "close");
    bridge.dispose();
    await closed;
    expect(
      bridge.send({ event: "panelScrollTo", filepath: jump.filepath, line: 2, character: 4 }),
    ).toBe(false);
  } finally {
    sockets.forEach((socket) => socket.terminate());
    bridge.dispose();
  }
});
