import { beforeEach, describe, expect, it, vi } from "vitest";
import { provideSvgDoc } from "./typst-doc.svg.mjs";
import { patchSvgToContainer } from "./typst-patch.svg.mjs";

vi.hoisted(() => {
  vi.stubGlobal("window", {});
});
vi.mock("./typst-patch.svg.mjs", () => ({ patchSvgToContainer: vi.fn() }));

function fixture() {
  let top = 0;
  let scale = 1;
  const rect = () => ({
    left: 0,
    top: -top,
    right: 400 * scale,
    bottom: 10000 * scale - top,
    width: 400 * scale,
    height: 10000 * scale,
  });
  const root = { getBoundingClientRect: rect };
  const scroller = {
    clientWidth: 400,
    scrollTop: 0,
    getBoundingClientRect: () => ({ top: 0, bottom: 600 }),
  };
  const init = vi.fn((_root: unknown, done?: () => void) => done?.());
  const render = vi.fn(() => "<svg/>");
  const pages = vi.fn(() => Array.from({ length: 20 }, () => ({ width: 400, height: 1000 })));
  class Context {
    disposeList: (() => void)[] = [];
    registerMode() {}
    previewMode = 0;
    partialRendering = true;
    documentGeneration = 1;
    currentScaleRatio = 1;
    cachedDOMState = { width: 400 };
    kModule = { render_in_window: render, retrievePagesInfo: pages };
    hookedElem = {
      firstElementChild: root,
      parentElement: scroller,
      ownerDocument: { defaultView: {} },
      getBoundingClientRect: rect,
    };
    windowElem = { initTypstSvg: init };
    r = { rescale: vi.fn() };
  }
  const Doc = provideSvgDoc(Context as any);
  const doc = new Doc() as any;
  return {
    doc,
    root,
    render,
    pages,
    init,
    scroll(value: number) {
      top = value;
      scroller.scrollTop = value;
    },
    zoom(value: number) {
      scale = value;
      doc.currentScaleRatio = value;
    },
  };
}

beforeEach(() => vi.clearAllMocks());

describe("partial SVG viewport reuse", () => {
  it("retains the SVG window and selection layout when scrolling inside the same pages", () => {
    const { doc, render, pages, init, scroll } = fixture();
    doc.rerender$svg();
    doc.postRender$svg();
    for (const top of [10, 20, 30]) {
      scroll(top);
      doc.rerender$svg();
      doc.postRender$svg();
    }
    expect(render).toHaveBeenCalledOnce();
    expect(pages).toHaveBeenCalledOnce();
    expect(patchSvgToContainer).toHaveBeenCalledOnce();
    expect(init).toHaveBeenCalledOnce();
    expect(render).toHaveBeenCalledWith(0, 0.01, 400, 1999.99);
  });

  it("refreshes the window and metadata after document data or reset changes its generation", () => {
    const { doc, render, pages, init } = fixture();
    doc.rerender$svg();
    doc.postRender$svg();
    doc.documentGeneration++;
    doc.rerender$svg();
    doc.postRender$svg();
    expect(render).toHaveBeenCalledTimes(2);
    expect(pages).toHaveBeenCalledTimes(2);
    expect(init).toHaveBeenCalledTimes(2);
  });

  it("renders a new page window but reuses metadata across long scrolls", () => {
    const { doc, render, pages, scroll } = fixture();
    doc.rerender$svg();
    scroll(5100);
    doc.rerender$svg();
    expect(render).toHaveBeenCalledTimes(2);
    expect(pages).toHaveBeenCalledOnce();
    expect(render).toHaveBeenLastCalledWith(0, 4000.01, 400, 6999.99);
  });

  it("redecorates page gaps and selectable geometry on zoom in the same page window", () => {
    const { doc, render, init, zoom } = fixture();
    doc.rerender$svg();
    doc.postRender$svg();
    zoom(1.25);
    doc.rerender$svg();
    doc.postRender$svg();
    expect(render).toHaveBeenCalledTimes(2);
    expect(init).toHaveBeenCalledTimes(2);
  });

  it("invalidates reuse when the root is replaced or partial rendering is toggled", () => {
    const { doc, root, render } = fixture();
    doc.rerender$svg();
    doc.hookedElem.firstElementChild = { ...root };
    doc.rerender$svg();
    doc.partialRendering = false;
    doc.rerender$svg();
    doc.partialRendering = true;
    doc.rerender$svg();
    expect(render).toHaveBeenCalledTimes(4);
  });

  it("does not reuse a window whose DOM patch failed", () => {
    const { doc, render } = fixture();
    vi.mocked(patchSvgToContainer).mockImplementationOnce(() => {
      throw new Error("patch");
    });
    expect(() => doc.rerender$svg()).toThrow("patch");
    doc.rerender$svg();
    expect(render).toHaveBeenCalledTimes(2);
  });

  it("retries touch layout if a selection holds its later animation frame", () => {
    const { doc, init } = fixture();
    init.mockImplementationOnce(() => {});
    doc.rerender$svg();
    doc.postRender$svg();
    doc.postRender$svg();
    expect(init).toHaveBeenCalledTimes(2);
    doc.postRender$svg();
    expect(init).toHaveBeenCalledTimes(2);
  });

  it("does not let a delayed layout mark a newer document as already initialized", () => {
    const { doc, init } = fixture();
    init.mockImplementation(() => {});
    doc.rerender$svg();
    doc.postRender$svg();
    const completeOldLayout = init.mock.calls[0][1]!;
    doc.documentGeneration++;
    doc.rerender$svg();
    completeOldLayout();
    doc.postRender$svg();
    expect(init).toHaveBeenCalledTimes(2);
  });
});
