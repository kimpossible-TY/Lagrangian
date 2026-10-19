import { describe, expect, it, vi } from "vitest";
import { createSelectionTransport } from "./transport";
import type { SelectedText } from "./text-selection";

const selection: SelectedText = {
  revision: "rendered-1",
  text: "Selected mathematics α + β",
  start: { page_no: 2, x: 10, y: 20 },
  end: { page_no: 3, x: 40, y: 50 },
  fragments: [{ page: 2, x: 10, y: 20, width: 30, height: 12 }],
  fingerprints: { 2: "page" },
};

describe("paged selection action transport", () => {
  it("keeps source writes and Codex capture on their existing native protocols", () => {
    const send = vi.fn(),
      announce = vi.fn();
    const submit = createSelectionTransport({
      ready: () => true,
      revision: () => "rendered-1",
      send,
      announce,
    });
    expect(submit("save", selection)).toBe(true);
    expect(submit("highlight", selection)).toBe(true);
    const payload = JSON.stringify({
      ...selection.start,
      revision: selection.revision,
      selection: { text: selection.text, end: selection.end },
    });
    expect(send.mock.calls).toEqual([[`src-point ${payload}`], [`src-highlight ${payload}`]]);
  });

  it("does not send a selection until the matching revision and connection are ready", () => {
    const send = vi.fn(),
      announce = vi.fn();
    let ready = false;
    let revision: string | undefined;
    const submit = createSelectionTransport({
      ready: () => ready,
      revision: () => revision,
      send,
      announce,
    });
    expect(submit("save", selection)).toBe(false);
    ready = true;
    expect(submit("highlight", selection)).toBe(false);
    revision = "rendered-2";
    expect(submit("save", selection)).toBe(false);
    expect(send).not.toHaveBeenCalled();
    revision = "rendered-1";
    expect(submit("save", selection)).toBe(true);
    expect(send).toHaveBeenCalledTimes(1);
  });
});
