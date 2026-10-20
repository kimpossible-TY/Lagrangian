import { afterEach, describe, expect, it, vi } from "vitest";
import { SelectionActions } from "./actions";
import { selectedPreviewText, type SelectedText } from "./text-selection";

vi.mock("./text-selection", () => ({ selectedPreviewText: vi.fn() }));
vi.mock("../review-strikes/renderer", () => ({
  ReviewMarkRenderer: class {
    store = { marks: [], add: vi.fn(), undo: vi.fn(), clear: vi.fn() };
    repaint = vi.fn();
    dispose = vi.fn();
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
  const page = Object.assign(new EventTarget(), {
    body: new Control(),
    createElement: () => new Control(),
  });
  vi.stubGlobal("document", page);
  vi.stubGlobal("navigator", { language: "en" });
  vi.stubGlobal("window", new EventTarget());
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
    () => "r1",
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
    event,
    collapse() {
      vi.mocked(selectedPreviewText).mockReturnValue(undefined);
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
