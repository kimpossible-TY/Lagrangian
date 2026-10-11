import { once } from "node:events";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { expect, test, vi } from "vitest";
import { WebSocket } from "ws";
import { attachFlowEditorRelay } from "../test/flow-editor-relay";
import { createBrowserEditorBridge } from "./shared-flow-browser";

vi.mock("../l10n", () => ({ l10nMsg: (message: string) => message }));

const channel = "12345678-1234-1234-1234-123456789abc";
const jump = { event: "editorScrollTo", filepath: "/project/main.typ", start: [2, 3], end: [2, 8] };

test("editor host and reader share one engine port, preserving both directions and independent disposal", async () => {
  const server = createServer((_request, response) => response.writeHead(200).end());
  const relay = attachFlowEditorRelay(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const reader = `http://127.0.0.1:${(server.address() as AddressInfo).port}/`;
  const reveal = vi.fn().mockResolvedValue(undefined);
  const bridge = await createBrowserEditorBridge(reader, channel, reveal);
  const socket = new WebSocket(
    new URL(`editor/${channel}?forwarding=preserved`, reader).toString().replace(/^http/, "ws"),
    { origin: new URL(reader).origin },
  );
  try {
    await once(socket, "open");
    await vi.waitFor(() => expect(bridge.connected).toBe(true));
    socket.send(JSON.stringify(jump));
    await vi.waitFor(() => expect(reveal).toHaveBeenCalledExactlyOnceWith(jump));
    const response = once(socket, "message");
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
    const closed = once(socket, "close");
    bridge.dispose();
    await closed;
    expect(bridge.connected).toBe(false);
    expect(
      bridge.send({ event: "panelScrollTo", filepath: jump.filepath, line: 2, character: 4 }),
    ).toBe(false);
    expect((await fetch(reader)).status).toBe(200);
  } finally {
    socket.terminate();
    bridge.dispose();
    relay.dispose();
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

test("editor host cannot connect to a remote endpoint", async () => {
  await expect(
    createBrowserEditorBridge("https://remote.example/", channel, vi.fn()),
  ).rejects.toThrow("loopback");
});
