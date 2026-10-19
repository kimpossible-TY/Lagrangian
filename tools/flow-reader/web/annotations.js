import { visualFragments } from "./math-identity.js";
import { languageOf, setLanguage, uiLanguage } from "./language.js";

export function shortAnnotation(text, rich = false) {
  const name = text.trim().replace(/\s+/gu, " ");
  const length =
    typeof Intl.Segmenter === "function"
      ? [...new Intl.Segmenter().segment(name)].length
      : [...name.normalize("NFC")].length;
  return !rich && name.length > 0 && length <= 24 && name.split(" ").length <= 3;
}

export function sideAnnotations({ width, height, articleRight, fontSize }) {
  return (
    width >= 960 &&
    width / height >= 1.15 &&
    width - articleRight >= Math.max(220, fontSize * 14) + 20
  );
}

export function popoverPosition(target, size, viewport) {
  const gap = 10;
  const above = target.top - viewport.top - gap;
  const below = viewport.bottom - target.bottom - gap;
  const onTop = above >= size.height || above > below;
  const height = Math.min(size.height, Math.max(44, onTop ? above : below));
  return {
    left: Math.max(
      viewport.left,
      Math.min((target.left + target.right - size.width) / 2, viewport.right - size.width),
    ),
    top: onTop ? Math.max(viewport.top, target.top - height - gap) : target.bottom + gap,
    maxHeight: height,
    side: onTop ? "above" : "below",
  };
}

const overlap = (a, b, gap = 3) =>
  a.left < b.right + gap &&
  a.right > b.left - gap &&
  a.top < b.bottom + gap &&
  a.bottom > b.top - gap;
const painted = (node) => !node.closest("mjx-assistive-mml,.flow-math-stage");

// Keep the authored note node once. Only its presentation changes; the original
// mathematical nodes and their canonical text never acquire UI label children.
export class TextAnnotations {
  constructor(article, { preserve, changed }) {
    Object.assign(this, { article, preserve, changed });
    this.records = new Map();
    this.resize = new ResizeObserver(() => this.schedule());
    this.resize.observe(article);
    this.mutations = new MutationObserver(() => this.schedule());
    this.mutations.observe(article, { childList: true, subtree: true });
    window.addEventListener("resize", () => this.schedule());
    window.addEventListener("scroll", () => this.schedule(), { passive: true });
    window.visualViewport?.addEventListener("resize", () => this.schedule());
    window.visualViewport?.addEventListener("scroll", () => this.schedule());
    document.fonts.addEventListener("loadingdone", () => this.schedule());
    document.addEventListener("selectionchange", () => this.schedule());
    article.addEventListener("click", (event) => this.activate(event));
    article.addEventListener("keydown", (event) => {
      if (!["Enter", " "].includes(event.key) || event.target.closest("button,a,input")) return;
      if (this.activate(event)) event.preventDefault();
    });
    document.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape" && this.active) {
          event.preventDefault();
          this.close(true);
        }
      },
      true,
    );
    document.addEventListener("pointerdown", (event) => {
      const target = event.target.closest("[data-reader-note]");
      if (
        this.active &&
        !this.active.note.contains(event.target) &&
        !(target?.dataset.readerNote ?? "").split(" ").includes(this.active.note.id)
      )
        this.close();
    });
  }

  register(nodes, note) {
    const body = document.createElement("div");
    body.className = "flow-note-body";
    body.append(...note.childNodes);
    note.append(body);
    const rich = Boolean(
      body.querySelector("a,img,svg,table,mi,mn,mo,mfrac,msqrt,msup,msub,msubsup"),
    );
    const record = {
      nodes: nodes.filter(Boolean),
      note,
      body,
      short: shortAnnotation(body.textContent, rich),
    };
    note.dataset.noteKind = "text";
    const close = document.createElement("button");
    close.type = "button";
    close.className = "flow-note-close";
    close.textContent = "×";
    close.setAttribute("aria-label", "주석 닫기");
    setLanguage(close, uiLanguage());
    close.addEventListener("click", () => this.close(true));
    note.prepend(close);
    note.addEventListener("toggle", (event) => {
      if (event.newState === "closed" && this.active === record) this.closed(record);
    });
    this.records.set(note.id, record);
    if (record.short) {
      for (const node of record.nodes)
        node.closest(".flow-equation,p")?.classList.add("flow-annotation-space");
    }
    // The visible body is also the no-JavaScript/diagnostic fallback. Hide it
    // only after a connected record has successfully entered an adaptive mode.
    return record;
  }

  clear() {
    this.close();
    this.records.clear();
    cancelAnimationFrame(this.frame);
    this.frame = null;
  }

  sync() {
    for (const [id, record] of this.records) {
      if (!record.note.isConnected) {
        if (this.active === record) this.close();
        this.records.delete(id);
      }
    }
    this.schedule();
  }

  schedule() {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.layout();
    });
  }

  fragments(record) {
    return record.nodes
      .flatMap(visualFragments)
      .filter((node) => node.isConnected && painted(node));
  }

  rectangles(record) {
    return this.fragments(record)
      .flatMap((node) => [...node.getClientRects()])
      .filter((rect) => rect.width > 0 && rect.height > 0);
  }

  place(note, left, top) {
    // Graphical scenes and authored callouts can establish a nearer positioned
    // ancestor than the article. Convert viewport coordinates for that parent.
    const parent = note.offsetParent ?? this.article;
    const origin = parent.getBoundingClientRect();
    note.style.left = `${left - origin.left - parent.clientLeft + parent.scrollLeft}px`;
    note.style.top = `${top - origin.top - parent.clientTop + parent.scrollTop}px`;
  }

  mode(record, mode) {
    const { note } = record;
    if (note.dataset.noteMode === mode) return;
    if (this.active === record) this.close();
    note.removeAttribute("popover");
    note.removeAttribute("role");
    note.style.cssText = "";
    note.dataset.noteMode = mode;
    note.hidden = mode === "popover";
    if (mode === "popover") {
      if (typeof note.showPopover === "function") note.setAttribute("popover", "auto");
      note.setAttribute("role", "dialog");
      note.setAttribute("aria-label", "주석");
    } else note.removeAttribute("aria-label");
  }

  layout() {
    const selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    const area = this.article.getBoundingClientRect();
    const fontSize = parseFloat(getComputedStyle(this.article).fontSize);
    const side = sideAnnotations({
      width: document.documentElement.clientWidth,
      height: innerHeight,
      articleRight: area.right,
      fontSize,
    });
    const layout = side ? "side" : "compact";
    if (this.article.dataset.annotationLayout !== layout) {
      this.preserve(() => {
        this.article.dataset.annotationLayout = layout;
      });
      this.changed();
      this.schedule();
      return;
    }
    const labels = [];
    let railBottom = -Infinity;
    for (const record of this.records.values()) {
      const { note } = record;
      if (note.classList.contains("flow-unresolved") || !record.nodes.length) continue;
      const rects = this.rectangles(record);
      if (!rects.length) {
        if (this.active === record) this.close();
        this.mode(record, "popover");
        continue;
      }
      const target = rects[0];
      if (side) {
        this.mode(record, "side");
        note.style.width = `${Math.min(320, document.documentElement.clientWidth - area.right - 20)}px`;
        const top = Math.max(target.top - area.top, railBottom);
        this.place(note, area.right + 20, area.top + top);
        railBottom = top + note.getBoundingClientRect().height + 16;
      } else if (
        record.short &&
        this.active !== record &&
        target.bottom > -500 &&
        target.top < innerHeight + 500
      ) {
        // Measuring a label temporarily changes its presentation. Keep an open
        // fallback popover in place until dismissal instead of closing it just
        // to discover the same collision again on the next layout pass.
        this.mode(record, "label");
        const size = note.getBoundingClientRect();
        const anchor = rects.at(-1);
        const host = this.fragments(record)[0]?.closest(".flow-equation,p");
        const ink = [
          ...(host?.querySelectorAll(
            "mjx-c,mjx-utext,mjx-stretchy-h,mjx-stretchy-v,mi,mn,mo,mtext",
          ) ?? []),
        ]
          .filter(painted)
          .flatMap((node) => [...node.getClientRects()]);
        // A preceding mathematical line can occupy the space above just one
        // end of a term. Try each local alignment before hiding a short name.
        const box = [
          anchor.right - size.width,
          anchor.left,
          (anchor.left + anchor.right - size.width) / 2,
        ]
          .map((position) => {
            const left = Math.max(area.left + 4, Math.min(position, area.right - size.width - 4));
            return {
              left,
              right: left + size.width,
              top: anchor.top - size.height - 6,
              bottom: anchor.top - 6,
            };
          })
          .find(
            (candidate) =>
              candidate.left >= area.left &&
              candidate.right <= area.right &&
              ![...ink, ...labels].some((rect) => overlap(candidate, rect)),
          );
        if (!box) this.mode(record, "popover");
        else {
          this.place(note, box.left, box.top);
          labels.push(box);
        }
      } else this.mode(record, "popover");
    }
    for (const record of this.records.values()) {
      for (const node of this.fragments(record)) {
        const ids = (node.dataset.readerNote ?? "").split(" ").filter(Boolean);
        const interactive = ids.some(
          (id) => this.records.get(id)?.note.dataset.noteMode === "popover",
        );
        if (interactive) {
          node.setAttribute("role", "button");
          node.setAttribute("tabindex", "0");
          node.setAttribute("aria-haspopup", "dialog");
          node.setAttribute("aria-controls", ids.join(" "));
          node.setAttribute("aria-expanded", String(ids.includes(this.active?.note.id)));
          node.dataset.noteInteractive = "true";
        } else {
          for (const attribute of [
            "role",
            "tabindex",
            "aria-haspopup",
            "aria-controls",
            "aria-expanded",
          ])
            node.removeAttribute(attribute);
          delete node.dataset.noteInteractive;
        }
      }
    }
    if (this.active) this.position(this.active);
  }

  activate(event) {
    if (!window.getSelection()?.isCollapsed || event.target.closest("a,button")) return false;
    const target = event.target.closest('[data-note-interactive="true"]');
    if (!target) return false;
    const choices = (target.dataset.readerNote ?? "")
      .split(" ")
      .map((id) => this.records.get(id))
      .filter((record) => record?.note.dataset.noteMode === "popover");
    if (!choices.length) return false;
    if (choices.includes(this.active)) this.close(true);
    else this.open(choices[0], target, choices);
    return true;
  }

  open(record, target, choices = [record]) {
    this.close();
    const { note } = record;
    this.active = record;
    record.trigger = target;
    note.hidden = false;
    const previous = note.querySelector(".flow-note-next");
    previous?.remove();
    if (choices.length > 1) {
      const next = document.createElement("button");
      next.type = "button";
      next.className = "flow-note-next";
      next.textContent = `다음 주석 (${choices.indexOf(record) + 1}/${choices.length})`;
      setLanguage(next, uiLanguage());
      next.addEventListener("click", () =>
        this.open(choices[(choices.indexOf(record) + 1) % choices.length], target, choices),
      );
      note.append(next);
    }
    note.dataset.open = "true";
    if (typeof note.showPopover === "function") note.showPopover();
    this.position(record);
    note.querySelector(".flow-note-close").focus({ preventScroll: true });
    this.changed();
    this.schedule();
  }

  position(record) {
    const rects = this.rectangles(record);
    const viewport = window.visualViewport;
    const top =
      Math.max(
        document.querySelector(".reader-toolbar")?.getBoundingClientRect().bottom ?? 0,
        viewport?.offsetTop ?? 0,
      ) + 12;
    const bottom = (viewport?.offsetTop ?? 0) + (viewport?.height ?? innerHeight) - 12;
    const target = rects.find((rect) => rect.bottom > top && rect.top < bottom);
    if (!target) {
      this.close();
      return;
    }
    const left = (viewport?.offsetLeft ?? 0) + 12;
    const right = left + (viewport?.width ?? document.documentElement.clientWidth) - 24;
    record.note.style.width = `${Math.min(right - left, 360)}px`;
    record.note.style.maxHeight = `${bottom - top}px`;
    const size = record.note.getBoundingClientRect();
    const placed = popoverPosition(target, size, { top, bottom, left, right });
    Object.assign(record.note.style, {
      left: `${placed.left}px`,
      top: `${placed.top}px`,
      maxHeight: `${placed.maxHeight}px`,
    });
    record.note.dataset.popoverSide = placed.side;
  }

  closed(record) {
    delete record.note.dataset.open;
    record.note.hidden = true;
    if (this.active === record) this.active = null;
    this.changed();
    this.schedule();
  }

  close(focus = false) {
    const record = this.active;
    if (!record) return;
    if (typeof record.note.hidePopover === "function" && record.note.matches(":popover-open"))
      record.note.hidePopover();
    this.closed(record);
    const target = record.trigger?.isConnected ? record.trigger : this.fragments(record)[0];
    if (focus) target?.focus({ preventScroll: true });
  }
}
