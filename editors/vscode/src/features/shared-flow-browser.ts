import * as http from "node:http";
import type { AddressInfo } from "node:net";

/** A small, per-reader callback endpoint; it carries source hits, never document frames. */
export async function createBrowserSourceBridge(
  readerOrigin: string,
  channel: string,
  reveal: (value: unknown) => Promise<void>,
): Promise<{ localUrl: string; dispose(): void }> {
  let busy = false;
  const route = `/source/${channel}`;
  const { createServer } = http;
  const server = createServer(async (request, response) => {
    if (
      new URL(request.url || "/", "http://localhost").pathname !== route ||
      request.headers.origin !== readerOrigin
    ) {
      response.writeHead(403).end();
      return;
    }
    response.setHeader("Access-Control-Allow-Origin", readerOrigin);
    response.setHeader("Vary", "Origin");
    response.setHeader("Cache-Control", "no-store");
    if (request.method === "OPTIONS") {
      response.setHeader("Access-Control-Allow-Methods", "POST");
      response.setHeader("Access-Control-Allow-Headers", "Content-Type");
      response.setHeader("Access-Control-Allow-Private-Network", "true");
      response.writeHead(204).end();
      return;
    }
    if (request.method !== "POST") {
      response.writeHead(405).end();
      return;
    }
    if (busy) {
      response.writeHead(429).end();
      return;
    }
    busy = true;
    try {
      const chunks: Uint8Array[] = [];
      let bytes = 0;
      for await (const raw of request) {
        const chunk = raw as Uint8Array;
        bytes += chunk.byteLength;
        if (bytes > 8192) {
          response.writeHead(413).end();
          return;
        }
        chunks.push(chunk);
      }
      let value: unknown;
      try {
        value = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      } catch {
        response.writeHead(400).end();
        return;
      }
      await reveal(value);
      response.writeHead(204).end();
    } catch {
      if (!response.headersSent) response.writeHead(500).end();
    } finally {
      busy = false;
    }
  });
  server.requestTimeout = 5000;
  server.headersTimeout = 5000;
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  return {
    localUrl: `http://127.0.0.1:${(server.address() as AddressInfo).port}${route}`,
    dispose() {
      server.closeAllConnections();
      server.close();
    },
  };
}
