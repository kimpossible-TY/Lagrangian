import { afterEach, describe, expect, it, vi } from "vitest";
import { SelectionActions } from "./actions";
import { selectedPreviewText, type SelectedText } from "./text-selection";
import { OptimisticHighlights } from "../../../../reader-common/source-highlight/optimistic.js";

const { paintOptimistic } = vi.hoisted(() => ({ paintOptimistic: vi.fn() }));

vi.mock("./text-selection", () => ({ selectedPreviewText: vi.fn() }));
vi.mock("../review-strikes/renderer", () => ({
  ReviewMarkRenderer: class {
    store = { marks: [], add: vi.fn(), undo: vi.fn(), clear: vi.fn(), setDocument: vi.fn() };
    repaint = vi.fn();
    dispose = vi.fn();
  },
}));
vi.mock("../source-highlight/renderer", () => ({
  SourceHighlightRenderer: class {
    highlights = new OptimisticHighlights(paintOptimistic);
    dispose() {
      this.highlights.dispose();
    }
  },
}));

class Control extends EventTarget {
  children: Control[] = [];
  hidden = false;
  disabled = false;
  setAttribute = vi.fn();
  remove = vi.fn();
  appendChild(control: Control) {
    this.children.push(control);
    return control;
  }
}

function fixture() {
  vi.useFakeTimers();
  const released = vi.fn();
  let revision = "r1";
  const page = Object.assign(new EventTarget(), {
    body: new Control(),
    createElement: () => new Control(),
    getSelection: () => ({ removeAllRanges: released }),
  });
  vi.stubGlobal("document", page);
  vi.stubGlobal("navigator", { language: "en" });
  vi.stubGlobal("window", new EventTarget());
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) =>
    setTimeout(callback, 0),
  );
  vi.stubGlobal("cancelAnimationFrame", clearTimeout);
  const selected: SelectedText = {
    text: "Selected",
    start: { page_no: 1, x: 10, y: 20 },
    end: { page_no: 1, x: 30, y: 20 },
    fragments: [],
    fingerprints: {},
  };
  vi.mocked(selectedPreviewText).mockReturnValue(selected);
  const submitted = vi.fn(() => true);
  const actions = new SelectionActions(
    new Control() as unknown as HTMLElement,
    submitted,
    () => revision,
  );
  actions.setEnabled(true);
  const toolbar = page.body.children[0];
  const save = toolbar.children[1];
  const event = (type: string) => {
    const event = new Event(type, { cancelable: true });
    save.dispatchEvent(event);
    return event;
  };
  return {
    actions,
    selected,
    save,
    toolbar,
    submitted,
    released,
    render(next: string) {
      revision = next;
      actions.setDocument("doc", next);
    },
    event,
    collapse() {
      vi.mocked(selectedPreviewText).mockReturnValue(undefined);
      page.dispatchEvent(new Event("selectionchange"));
    },
    select() {
      vi.mocked(selectedPreviewText).mockReturnValue({ ...selected });
      page.dispatchEvent(new Event("selectionchange"));
    },
  };
}

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

describe("paged selection toolbar interaction", () => {
  it("paints immediately, releases native selection and waits for the rendered revision", () => {
    const h = fixture();
    h.render("r1");
    h.toolbar.children[0].dispatchEvent(new Event("click"));
    expect(paintOptimistic).toHaveBeenLastCalledWith([h.selected]);
    expect(h.released).toHaveBeenCalledOnce();
    h.collapse();
    h.actions.highlightFinished("highlighted");
    h.render("r1");
    expect(paintOptimistic).toHaveBeenLastCalledWith([h.selected]);
    h.render("r2");
    expect(paintOptimistic).toHaveBeenLastCalledWith([]);
    h.actions.dispose();
  });

  it("rolls back rejected paint while preserving a newer selection", () => {
    const h = fixture();
    h.toolbar.children[0].dispatchEvent(new Event("click"));
    h.select();
    h.actions.highlightFinished("unsupported");
    expect(paintOptimistic).toHaveBeenLastCalledWith([]);
    expect(h.save.disabled).toBe(false);
    h.actions.dispose();
  });

  it("keeps rejected retry context through a late native selectionchange", () => {
    const h = fixture();
    h.toolbar.children[0].dispatchEvent(new Event("click"));
    h.collapse();
    h.actions.highlightFinished("unsupported");
    h.collapse();
    expect(h.save.hidden).toBe(false);
    expect(h.save.disabled).toBe(false);
    h.render("r2");
    vi.runAllTimers();
    expect(h.save.hidden).toBe(true);
    h.actions.dispose();
  });

  it("abandons an undeliverable highlight acknowledgment without replaying the mutation", () => {
    const h = fixture();
    const highlight = h.toolbar.children[0];
    highlight.dispatchEvent(new Event("click"));
    expect(h.submitted).toHaveBeenCalledExactlyOnceWith("highlight", h.selected);
    expect(h.save.disabled).toBe(true);
    h.actions.connectionLost();
    expect(paintOptimistic).toHaveBeenLastCalledWith([]);
    expect(h.save.disabled).toBe(true);
    h.collapse();
    h.select();
    h.actions.setEnabled(true);
    expect(h.save.disabled).toBe(false);
    expect(h.submitted).toHaveBeenCalledOnce();
    h.actions.dispose();
  });

  it("retains its pressed page selection and controls through native collapse until click", () => {
    const h = fixture();
    expect(h.event("pointerdown").defaultPrevented).toBe(true);
    expect(h.event("mousedown").defaultPrevented).toBe(true);
    h.collapse();
    h.event("pointerup");
    expect(h.save.hidden).toBe(false);
    expect(h.save.disabled).toBe(false);
    h.event("click");
    expect(h.submitted).toHaveBeenCalledWith("save", h.selected);
    expect(h.save.hidden).toBe(true);
    vi.runAllTimers();
    expect(h.submitted).toHaveBeenCalledOnce();
    h.actions.dispose();
  });

  it("updates collapsed controls after pointer cancellation and disposes deferred feedback", () => {
    const h = fixture();
    h.event("pointerdown");
    h.collapse();
    h.event("pointercancel");
    expect(h.save.hidden).toBe(false);
    vi.runAllTimers();
    expect(h.save.hidden).toBe(true);
    expect(h.submitted).not.toHaveBeenCalled();
    h.event("pointerdown");
    h.event("pointerup");
    expect(vi.getTimerCount()).toBe(1);
    h.actions.dispose();
    expect(vi.getTimerCount()).toBe(0);
    expect(h.toolbar.remove).toHaveBeenCalledOnce();
  });
});
