// Browser-change signals only. Actual frame bytes still come from page.screenshot.
import { createHash } from "node:crypto";

// Capture the whole viewport even though only change detection uses the result:
// a scaled-down screencast lets Chromium discard the full-size capture surface,
// making the next screenshot after an idle period take seconds. Low quality
// keeps these discarded signal frames small.
const screencastOptions = { format: "jpeg", quality: 1 };

function frameDigest(data) {
  return createHash("sha256").update(data).digest("hex");
}

export async function startScreencastSignals(page, onFrame) {
  const context = page.context?.();
  if (typeof context?.newCDPSession === "function") {
    const session = await context.newCDPSession(page);
    let digest = null;
    let baseline = true;
    const listener = (frame) => {
      // Acknowledge every frame before requesting work, so a slow presentation
      // cannot stall the browser's change stream.
      Promise.resolve(
        session.send("Page.screencastFrameAck", { sessionId: frame.sessionId }),
      ).catch(() => {});
      // Taking our own screenshot also makes Chromium emit an identical frame.
      // Its bytes match the previous frame, so it is not a document change.
      const next = frameDigest(frame.data);
      if (next === digest) return;
      digest = next;
      if (baseline) {
        // The initial frame is covered by the host's mandatory first capture.
        baseline = false;
        return;
      }
      onFrame();
    };
    session.on("Page.screencastFrame", listener);
    try {
      await session.send("Page.startScreencast", screencastOptions);
    } catch (error) {
      session.off?.("Page.screencastFrame", listener);
      await session.detach?.().catch(() => {});
      throw new Error(`Reader change detection could not start: ${error.message}`);
    }
    return async () => {
      session.off?.("Page.screencastFrame", listener);
      await session.send("Page.stopScreencast").catch(() => {});
      await session.detach?.().catch(() => {});
    };
  }
  if (typeof page.startScreencast === "function") {
    let digest = null;
    let baseline = true;
    const listener = (frame) => {
      Promise.resolve(page.screencastFrameAck?.({ sessionId: frame.sessionId })).catch(() => {});
      const next = frameDigest(frame.data);
      if (next === digest) return;
      digest = next;
      if (baseline) {
        baseline = false;
        return;
      }
      onFrame();
    };
    page.on("screencastFrame", listener);
    await page.startScreencast(screencastOptions);
    return async () => {
      page.off?.("screencastFrame", listener);
      await page.stopScreencast?.().catch(() => {});
    };
  }
  throw new Error("Reader change detection requires a Chromium page with CDP screencast support.");
}
