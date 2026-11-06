import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import test from "node:test";
import { readerLink } from "../web/ui/reader-links.js";

test("browser links inherit the server's single loopback host and normalized URLs", () => {
  const fixture = JSON.parse(
    execFileSync(
      "python3",
      [
        "-c",
        `import json
from flow_reader.services.homepage import LOOPBACK_HOST, reader_url
values = [f"http://{LOOPBACK_HOST}:8769", "https://home.example",
          "http://localhost:8769/", "http://[::1]:8769/", "http://remote.example/",
          "javascript:alert(1)", "https://user:password@home.example/",
          "https://home.example/path", "https://home.example/?secret=x"]
print(json.dumps({"host": LOOPBACK_HOST, "urls": [reader_url(v) for v in values]}))`,
      ],
      { cwd: new URL("..", import.meta.url), encoding: "utf8" },
    ),
  );
  assert.equal(new URL(fixture.urls[0]).hostname, fixture.host);
  assert.deepEqual(fixture.urls.slice(2), Array(7).fill(null));
  assert.deepEqual(fixture.urls.map(readerLink), fixture.urls);
  assert.equal(readerLink(undefined), null);
  for (const value of ["javascript:alert(1)", "data:text/html,x", "file:///tmp/source"])
    assert.equal(readerLink(value), null);
});
