import { afterEach, describe, expect, it, vi } from "vitest";
import { ReadingRecovery } from "./reading-recovery";
import { captureReferenceOrigin, restoreReferenceOrigin } from "../navigation/reference-navigation";
import { previewPages } from "../selection/text-selection";

vi.mock("../navigation/reference-navigation", () => ({
  captureReferenceOrigin: vi.fn(),
  restoreReferenceOrigin: vi.fn(() => true),
}));
vi.mock("../selection/text-selection", () => ({ previewPages: vi.fn() }));

function fixture() {
  const page = new EventTarget();
  const scroller = new EventTarget() as HTMLElement;
  const root = { ownerDocument: page } as HTMLElement;
  vi.mocked(captureReferenceOrigin).mockReturnValue({ page: 2, x: 0.1, y: 0.25 });
  const fingerprint = (value: string) =>
    vi.mocked(previewPages).mockReturnValue(new Map([[3, { fingerprint: value } as any]]));
  fingerprint("same-text-and-layout");
  const recovery = new ReadingRecovery(scroller, root);
  recovery.afterRender("document-a", "4");
  return { recovery, scroller, root, page, fingerprint };
}

afterEach(() => vi.clearAllMocks());

describe("full document reading recovery", () => {
  it("restores the verified page across a restart revision reset", () => {
    const h = fixture();
    h.recovery.beforeReset();
    expect(h.recovery.afterRender("document-a", "1")).toBe(true);
    expect(restoreReferenceOrigin).toHaveBeenCalledWith(
      { page: 2, x: 0.1, y: 0.25 },
      h.scroller,
      h.root,
    );
    expect(h.recovery.afterRender("document-a", "1")).toBe(false);
    h.recovery.dispose();
  });

  it.each([undefined, "document-b"])("never applies an anchor to identity %s", (document) => {
    const h = fixture();
    h.recovery.beforeReset();
    expect(h.recovery.afterRender(document, "4")).toBe(false);
    expect(restoreReferenceOrigin).not.toHaveBeenCalled();
    h.recovery.dispose();
  });

  it("rejects changed page contents even when a restarted engine repeats a revision", () => {
    const h = fixture();
    h.recovery.beforeReset();
    h.fingerprint("changed-layout");
    expect(h.recovery.afterRender("document-a", "4")).toBe(false);
    expect(restoreReferenceOrigin).not.toHaveBeenCalled();
    h.recovery.dispose();
  });

  it("does not override navigation begun while a replacement is rendering", () => {
    const h = fixture();
    h.recovery.beforeReset();
    h.scroller.dispatchEvent(new Event("wheel"));
    expect(h.recovery.afterRender("document-a", "5")).toBe(false);
    h.recovery.beforeReset();
    h.page.dispatchEvent(new Event("keydown"));
    expect(h.recovery.afterRender("document-a", "6")).toBe(false);
    expect(restoreReferenceOrigin).not.toHaveBeenCalled();
    h.recovery.dispose();
  });

  it("captures when rendering begins and discards unavailable or disposed snapshots", () => {
    const h = fixture();
    vi.mocked(captureReferenceOrigin).mockReturnValue({ page: 2, x: 0, y: 0.8 });
    h.recovery.beforeReset();
    h.recovery.dispose();
    expect(h.recovery.afterRender("document-a", "1")).toBe(false);
    h.recovery.beforeReset();
    vi.mocked(previewPages).mockReturnValue(new Map());
    expect(h.recovery.afterRender("document-a", "1")).toBe(false);
    expect(restoreReferenceOrigin).not.toHaveBeenCalled();
  });
});
