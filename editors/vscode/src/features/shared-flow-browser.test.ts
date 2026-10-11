import { expect, test, vi } from "vitest";
import { createBrowserSourceBridge } from "./shared-flow-browser";

test("external reader callbacks require their exact origin and session route", async () => {
  const reveal = vi.fn().mockResolvedValue(undefined);
  const bridge = await createBrowserSourceBridge(
    "http://localhost:23625",
    "unique-session",
    reveal,
  );
  try {
    const body = JSON.stringify({ filepath: "/project/main.typ", line: 3, column: 8 });
    const headers = { Origin: "http://localhost:23625", "Content-Type": "application/json" };
    expect((await fetch(bridge.localUrl, { method: "POST", body })).status).toBe(403);
    expect(
      (
        await fetch(bridge.localUrl, {
          method: "POST",
          headers: { Origin: "https://other.example" },
          body,
        })
      ).status,
    ).toBe(403);
    expect(
      (
        await fetch(bridge.localUrl.replace("unique-session", "other"), {
          method: "POST",
          headers,
          body,
        })
      ).status,
    ).toBe(403);
    expect((await fetch(bridge.localUrl, { headers })).status).toBe(405);
    expect(reveal).not.toHaveBeenCalled();
    const preflight = await fetch(bridge.localUrl, { method: "OPTIONS", headers });
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("Access-Control-Allow-Origin")).toBe(headers.Origin);
    expect(
      (await fetch(bridge.localUrl, { method: "POST", headers, body: "bad json" })).status,
    ).toBe(400);
    const response = await fetch(bridge.localUrl + "?forwarding=preserved", {
      method: "POST",
      headers,
      body,
    });
    expect(response.status).toBe(204);
    expect(reveal).toHaveBeenCalledExactlyOnceWith(JSON.parse(body));
  } finally {
    bridge.dispose();
  }
  await expect(fetch(bridge.localUrl)).rejects.toThrow();
});
