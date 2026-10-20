import { logicalTextIndex } from "../../rendering/math/identity.js";

/** HTML passage and native-canvas anchors; no page-coordinate approximation. */
export function createReadingPosition(article, { readBlocks, readSection }) {
  let stableAnchor = null;
  let stableScrollY = scrollY;
  let anchorWidth = document.documentElement.clientWidth;
  let holding = false;
  const textOf = (node) => logicalTextIndex(node).text;
  function capture() {
    // Explicit returns keep their intended anchor through asynchronous composition.
    if (holding) return stableAnchor;
    const parked = [...article.querySelectorAll('[data-section-state="parked"]')].find((node) => {
      const rect = node.getBoundingClientRect();
      return rect.top <= 90 && rect.bottom > 90;
    });
    if (parked) {
      const rect = parked.getBoundingClientRect();
      return {
        section: parked.dataset.readerSection,
        fraction: (90 - rect.top) / rect.height,
        url: location.href,
      };
    }
    for (const canvas of article.querySelectorAll("[data-flow-canvas-model]")) {
      const area = canvas.getBoundingClientRect();
      if (area.top > 90 || area.bottom <= 90) continue;
      const labels = readBlocks()
        .filter((node) => node.closest("[data-flow-canvas-model]") === canvas)
        .map((node) => ({ node, rect: node.getBoundingClientRect() }))
        .filter(({ rect }) => rect.height > 0 && rect.top <= 90 && rect.bottom > 90)
        .sort((a, b) => a.rect.left - b.rect.left);
      if (labels.length) {
        const { node, rect } = labels[0];
        return {
          key: node.dataset.readerKey,
          canvasIdentity: canvas.dataset.flowCanvasIdentity,
          text: textOf(node).slice(0, 180),
          offset: Math.round(rect.top) - 90,
          id: node.id,
          url: location.href,
          section: node.closest("[data-reader-section]")?.dataset.readerSection ?? readSection(),
        };
      }
      const geometry = canvas.querySelector(
        ":scope > .flow-canvas-stage > svg:not(.flow-canvas-leaders)",
      );
      const rect = geometry?.getBoundingClientRect();
      const plane = canvas.querySelector(":scope > .flow-canvas-stage")?.getBoundingClientRect();
      if (rect?.height > 0 && plane?.top <= 90 && plane.bottom > 90) {
        return {
          canvas: canvas.id,
          canvasIdentity: canvas.dataset.flowCanvasIdentity,
          canvasFraction: (90 - rect.top) / rect.height,
          text: logicalTextIndex(canvas, { includeNested: true }).text.slice(0, 180),
          section: canvas.closest("[data-reader-section]")?.dataset.readerSection ?? readSection(),
          id: canvas.id,
          url: location.href,
        };
      }
    }
    const block = readBlocks().find((node) => node.getBoundingClientRect().bottom > 90);
    if (!block) return null;
    return {
      key: block.dataset.readerKey,
      text: textOf(block).slice(0, 180),
      // CSS scroll positions are rounded. Keep one pixel target so hundreds of
      // automatic label publications cannot accumulate fractional scroll errors.
      offset: Math.round(block.getBoundingClientRect().top) - 90,
      section: block.closest("[data-reader-section]")?.dataset.readerSection ?? readSection(),
      id: block.id,
      url: location.href,
    };
  }
  function restore(anchor) {
    if (!anchor) return false;
    if (anchor.canvas && Number.isFinite(anchor.canvasFraction)) {
      const matchesText = (node) =>
        node?.hasAttribute("data-flow-canvas-model") &&
        logicalTextIndex(node, { includeNested: true }).text.startsWith(anchor.text);
      const matches = (node) =>
        matchesText(node) &&
        (!anchor.canvasIdentity || node.dataset.flowCanvasIdentity === anchor.canvasIdentity);
      let canvas = document.getElementById(anchor.canvas);
      if (!matches(canvas)) {
        const candidates = [...article.querySelectorAll("[data-flow-canvas-model]")].filter(
          matches,
        );
        canvas = candidates.length === 1 ? candidates[0] : null;
      }
      if (!canvas && anchor.canvasIdentity) {
        const candidates = [...article.querySelectorAll("[data-flow-canvas-model]")].filter(
          matchesText,
        );
        canvas = candidates.length === 1 ? candidates[0] : null;
      }
      const rect = canvas
        ?.querySelector(":scope > .flow-canvas-stage > svg:not(.flow-canvas-leaders)")
        ?.getBoundingClientRect();
      if (rect?.height > 0) {
        window.scrollBy(0, rect.top + rect.height * anchor.canvasFraction - 90);
        if (document.documentElement.clientWidth === anchorWidth) {
          stableAnchor = anchor;
          stableScrollY = scrollY;
        }
        return true;
      }
      return false;
    }
    if (Number.isFinite(anchor.fraction)) {
      const section = article.querySelector(
        `[data-reader-section="${CSS.escape(anchor.section)}"]`,
      );
      if (section) {
        const rect = section.getBoundingClientRect();
        window.scrollBy(0, rect.top + rect.height * anchor.fraction - 90);
        if (document.documentElement.clientWidth === anchorWidth) {
          stableAnchor = anchor;
          stableScrollY = scrollY;
        }
        return true;
      }
      return false;
    }
    const candidates = readBlocks().filter(
      (node) =>
        textOf(node).startsWith(anchor.text) &&
        (!anchor.canvasIdentity ||
          node.closest("[data-flow-canvas-model]")?.dataset.flowCanvasIdentity ===
            anchor.canvasIdentity),
    );
    const block =
      readBlocks().find((node) => node.dataset.readerKey === anchor.key) ??
      (candidates.length === 1 ? candidates[0] : null);
    if (block) {
      window.scrollBy(0, block.getBoundingClientRect().top - 90 - anchor.offset);
      if (document.documentElement.clientWidth === anchorWidth) {
        stableAnchor = anchor;
        stableScrollY = scrollY;
      }
      return true;
    }
    return false;
  }

  const remember = (anchor = capture()) => {
    if (holding) return;
    if (document.documentElement.clientWidth !== anchorWidth) return;
    stableAnchor = anchor;
    stableScrollY = scrollY;
  };
  const resized = () => {
    // Visual pinch zoom must not restore an obsolete layout-width anchor.
    const width = document.documentElement.clientWidth;
    if (width === anchorWidth) return;
    anchorWidth = width;
    restore(stableAnchor);
  };
  const fontsLoaded = () => {
    if (holding || Math.abs(scrollY - stableScrollY) < 1) restore(stableAnchor);
  };
  window.addEventListener("resize", resized);
  document.fonts.addEventListener("loadingdone", fontsLoaded);
  const release = () => {
    holding = false;
  };
  const gestures = ["pointerdown", "touchmove", "wheel", "keydown"];
  for (const event of gestures) document.addEventListener(event, release, { passive: true });
  return {
    capture,
    restore,
    remember,
    hold(anchor) {
      holding = restore(anchor);
      return holding;
    },
    release,
    dispose() {
      release();
      window.removeEventListener("resize", resized);
      document.fonts.removeEventListener("loadingdone", fontsLoaded);
      for (const event of gestures) document.removeEventListener(event, release);
    },
  };
}
