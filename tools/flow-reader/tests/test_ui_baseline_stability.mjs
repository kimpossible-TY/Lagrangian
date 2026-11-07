import { test } from "node:test";
import assert from "node:assert/strict";
import { stableScreenshot } from "./ui-baseline-stability.mjs";

test("capture waits for consecutive matching frames and counts retries", async () => {
  const frames = ["a", "b", "b"].map((frame) => Buffer.from(frame));
  const result = await stableScreenshot(async () => frames.shift(), { wait: async () => {} });
  assert.equal(result.image.toString(), "b");
  assert.equal(result.retryCount, 2);
  assert.equal(result.unstable, undefined);
});

test("capture reports instability when the retry limit is reached", async () => {
  let frame = 0;
  const result = await stableScreenshot(async () => Buffer.from(String(frame++)), { attempts: 3, wait: async () => {} });
  assert.equal(result.unstable, true);
  assert.equal(result.retryCount, 2);
});
