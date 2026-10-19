import { logicalTextIndex, visualFragments } from "./math-identity.js";
import { setLanguage, uiLanguage } from "./language.js";
import { routeConnection } from "./connector-routing.js";

export function shortAnnotation(text, rich = false) {
  const name = text.trim().replace(/\s+/gu, " ");
  const length =
    typeof Intl.Segmenter === "function"
      ? [...new Intl.Segmenter().segment(name)].length
      : [...name.normalize("NFC")].length;
  return !rich && name.length > 0 && length <= 24 && name.split(" ").length <= 3;
}

export function sideAnnotations({ width, height, articleWidth, fontSize }) {
  return (
    width >= 960 &&
    width / height >= 1.15 &&
    articleWidth >= Math.max(360, fontSize * 26) + Math.max(220, fontSize * 14) + 20
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

const painted = (node) => !node.closest("mjx-assistive-mml,.flow-math-stage");

function inkRectangles(host) {
  const ink = [
    ...host.querySelectorAll(
      "mjx-c,mjx-utext,mjx-stretchy-h,mjx-stretchy-v,mi,mn,mo,mtext,.flow-equation-number",
    ),
  ]
    .filter(painted)
    .flatMap((node) => [...node.getClientRects()]);
  const text = document.createTreeWalker(host, NodeFilter.SHOW_TEXT);
  for (let node = text.nextNode(); node; node = text.nextNode()) {
    if (
      !node.data.trim() ||
      node.parentElement.closest(
        "math,.flow-math-view,.flow-note,svg,.flow-math-status,.flow-decoration-notice",
      )
    )
      continue;
    const range = document.createRange();
    range.selectNodeContents(node);
    ink.push(...range.getClientRects());
  }
  return ink.filter((rect) => rect.width > 0 && rect.height > 0);
}

export function labelPosition(target, size, bounds, obstacles) {
  const gap = 6;
  if (size.width > bounds.right - bounds.left) return null;
  const idealTop = target.top - size.height - gap;
  const idealLeft = (target.left + target.right - size.width) / 2;
  const tops = [
    ...new Set([idealTop, bounds.top, ...obstacles.map((rect) => rect.top - size.height - gap)]),
  ].filter((top) => top >= bounds.top && top <= idealTop);
  let best = null;
  let distance = Infinity;
  for (const top of tops) {
    // Project only ink crossing this row onto the horizontal axis. The gaps
    // between merged intervals are usable even when the full equation box is not.
    const blocked = obstacles
      .filter((rect) => top < rect.bottom + 3 && top + size.height > rect.top - 3)
      .map((rect) => [Math.max(bounds.left, rect.left - 3), Math.min(bounds.right, rect.right + 3)])
      .filter(([left, right]) => left < right)
      .sort((a, b) => a[0] - b[0]);
    let left = bounds.left;
    for (const [start, end] of [...blocked, [bounds.right, bounds.right]]) {
      if (start - left >= size.width) {
        const x = Math.max(left, Math.min(idealLeft, start - size.width));
        const score = (idealTop - top) * 2 + Math.abs(x - idealLeft);
        if (score < distance) {
          best = { left: x, right: x + size.width, top, bottom: top + size.height };
          distance = score;
        }
      }
      left = Math.max(left, end);
    }
  }
  return best;
}

// Keep the authored note node once. Only its presentation changes; the original
// mathematical nodes and their canonical text never acquire UI label children.
export class TextAnnotations {
  constructor(article, { preserve, changed, loadFootnote, prepareNote }) {
    Object.assign(this, { article, preserve, changed, loadFootnote, prepareNote });
    this.records = new Map();
    this.reserved = new Map();
    this.sides = new Map();
    this.resize = new ResizeObserver(() => this.schedule());
    this.resize.observe(article);
    this.mutations = new MutationObserver(() => this.schedule());
    this.mutations.observe(article, { childList: true, subtree: true });
    window.addEventListener("resize", () => this.schedule());
    window.addEventListener("scroll", () => this.schedule(), { passive: true });
    window.visualViewport?.addEventListener("resize", () => this.schedule());
    window.visualViewport?.addEventListener("scroll", () => this.schedule());
    document.fonts.addEventListener("loadingdone", () => {
      for (const record of this.records.values()) delete record.sideSize;
      this.schedule();
    });
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

  register(nodes, note, { kind = "text", number = "", load = null } = {}) {
    const body = document.createElement("div");
    body.className = "flow-note-body";
    body.append(...note.childNodes);
    note.append(body);
    const rich = Boolean(
      body.querySelector("a,img,svg,table,mfrac,msqrt,mroot,mtable,munder,mover,munderover"),
    );
    const record = {
      nodes: nodes.filter(Boolean),
      note,
      body,
      kind,
      number,
      load,
      short:
        kind === "text" &&
        shortAnnotation(
          logicalTextIndex(body, { includeNotes: true, includeNested: true }).text,
          rich,
        ),
    };
    note.dataset.noteKind = kind;
    note.dataset.noteShort = String(record.short);
    const reference = document.createElement("div");
    reference.className = "flow-note-reference";
    reference.setAttribute("aria-hidden", "true");
    note.prepend(reference);
    record.reference = reference;
    if (load) note.hidden = true;
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

  prepareFootnotes(root, section) {
    const hosts = new Map();
    let count = 0;
    for (const reference of root.querySelectorAll('[role="doc-noteref"]')) {
      if (reference.closest('a,nav,[role="doc-endnotes"],.flow-notes')) continue;
      const link = reference.querySelector('a[href^="#"]');
      const host = reference.closest(".flow-equation,p,h1,h2,h3,h4,h5,h6,li");
      if (!link || !host) continue;
      let target;
      try {
        target = decodeURIComponent(link.hash.slice(1));
      } catch {
        continue;
      }
      if (!hosts.has(host)) {
        const group = document.createElement("aside");
        group.className = "flow-notes";
        host.after(group);
        hosts.set(host, { notes: new Map(), group });
      }
      const { notes, group } = hosts.get(host);
      let record = notes.get(target);
      const source = reference.closest("mtext") ?? reference;
      // Let MathIdentity bind HTML footnote markers inside composed mathematics.
      if (source.closest("math")) source.dataset.flowMark = `footnote-${section}-${++count}`;
      if (!record) {
        const note = document.createElement("div");
        note.className = "flow-note";
        note.id = `reader-footnote-${section}-${++count}`;
        note.dataset.footnoteTarget = target;
        group.append(note);
        record = this.register([], note, {
          kind: "footnote",
          number: link.textContent.trim(),
          load: () => this.loadFootnote(target),
        });
        notes.set(target, record);
      }
      record.nodes.push(source);
      source.dataset.readerNote = [source.dataset.readerNote, record.note.id]
        .filter(Boolean)
        .join(" ");
    }
  }

  async load(record) {
    if (record.loading || record.retryAt > Date.now()) return;
    record.loading = true;
    try {
      const body = await record.load();
      if (this.records.get(record.note.id) !== record || !record.note.isConnected) return;
      if (!body) throw new Error("Footnote unavailable");
      setLanguage(record.note, body.closest("[lang]")?.getAttribute("lang") ?? "");
      body.querySelectorAll('[role="doc-backlink"]').forEach((node) => node.remove());
      const ids = new Map(
        [...body.querySelectorAll("[id]")].map((node, index) => [
          node.id,
          `${record.note.id}-content-${index}`,
        ]),
      );
      for (const node of body.querySelectorAll("*")) {
        if (node.id) node.id = ids.get(node.id);
        for (const attribute of [...node.attributes]) {
          let value = attribute.value.replace(/url\(#([^)]*)\)/gu, (match, id) =>
            ids.has(id) ? `url(#${ids.get(id)})` : match,
          );
          if (value.startsWith("#") && ids.has(value.slice(1)))
            value = `#${ids.get(value.slice(1))}`;
          if (value !== attribute.value) node.setAttribute(attribute.name, value);
        }
      }
      record.body.append(...body.childNodes);
      record.load = null;
      this.prepareNote(record.note);
      this.changed();
      this.schedule();
    } catch {
      // The original endnote link remains usable; retry after reconnect/resize.
      record.retryAt = Date.now() + 5000;
    } finally {
      record.loading = false;
    }
  }

  footnote(target) {
    return [...this.records.values()].find(
      (record) =>
        record.note.dataset.footnoteTarget === target && record.note.dataset.noteMode === "side",
    )?.note;
  }

  clear() {
    this.close();
    this.records.clear();
    for (const host of this.reserved.keys()) host.style.removeProperty("--flow-annotation-padding");
    this.reserved.clear();
    for (const host of this.sides.keys()) this.clearSide(host);
    this.sides.clear();
    cancelAnimationFrame(this.frame);
    this.frame = null;
  }

  sync() {
    for (const host of this.sides.keys()) {
      if (!host.isConnected) {
        this.clearSide(host);
        this.sides.delete(host);
      }
    }
    for (const host of this.reserved.keys()) {
      if (!host.isConnected) {
        host.style.removeProperty("--flow-annotation-padding");
        this.reserved.delete(host);
      }
    }
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
    note.hidden = mode === "popover" || mode === "endnote";
    if (mode === "popover") {
      if (typeof note.showPopover === "function") note.setAttribute("popover", "auto");
      note.setAttribute("role", "dialog");
      note.setAttribute("aria-label", "주석");
    } else if (record.kind === "footnote" && mode === "side") {
      note.setAttribute("role", "note");
      note.setAttribute("aria-label", record.number);
      note.setAttribute("tabindex", "-1");
    } else {
      note.removeAttribute("aria-label");
      note.removeAttribute("tabindex");
    }
  }

  clearSide(host) {
    this.sides.get(host)?.lines?.remove();
    host.classList.remove("flow-annotation-side");
    host.style.removeProperty("--flow-side-width");
    host.style.removeProperty("--flow-side-height");
  }

  sideGroups(enabled, fontSize) {
    const groups = new Map();
    if (enabled) {
      for (const record of this.records.values()) {
        if (record.note.classList.contains("flow-unresolved")) continue;
        const host = this.fragments(record)[0]?.closest(".flow-equation,p,h1,h2,h3,h4,h5,h6,li");
        if (
          !host ||
          !sideAnnotations({
            width: document.documentElement.clientWidth,
            height: innerHeight,
            articleWidth: host.getBoundingClientRect().width,
            fontSize,
          })
        )
          continue;
        if (record.load) {
          this.load(record);
          continue;
        }
        if (!groups.has(host)) groups.set(host, { records: [] });
        groups.get(host).records.push(record);
      }
    }
    for (const [host, group] of groups) {
      group.lines = this.sides.get(host)?.lines;
      const width = Math.max(220, fontSize * 14);
      group.width = 0;
      for (const record of group.records) {
        const reference =
          record.kind === "footnote"
            ? record.number
            : (host.querySelector(".flow-equation-number")?.textContent.trim() ?? "");
        if (record.reference.textContent !== reference) {
          record.reference.textContent = reference;
          delete record.sideSize;
        }
        this.mode(record, "side");
        let natural = width;
        if (record.short) {
          const key = `${fontSize}:${[...record.body.querySelectorAll(".flow-math-view")]
            .map((node) => node.dataset.mathState)
            .join(",")}`;
          if (record.sideSize?.key !== key) {
            record.note.style.width = "max-content";
            record.sideSize = { key, width: Math.ceil(record.note.getBoundingClientRect().width) };
          }
          natural = record.sideSize.width;
        }
        group.width = Math.max(group.width, Math.min(width, natural));
      }
      for (const record of group.records) {
        const value = `${group.width}px`;
        if (record.note.style.width !== value) record.note.style.width = value;
      }
      group.height =
        group.records.reduce((sum, record) => sum + record.note.getBoundingClientRect().height, 0) +
        (group.records.length - 1) * 16;
      const style = getComputedStyle(host);
      group.top = Math.max(8, parseFloat(style.fontSize) * 0.6);
      group.bottom = parseFloat(style.paddingBottom);
      group.minimum = Math.ceil(group.height + group.top + group.bottom);
    }
    const changed =
      [...this.sides.keys()].some((host) => !groups.has(host)) ||
      [...groups].some(([host, group]) => {
        const previous = this.sides.get(host);
        return !previous || previous.width !== group.width || previous.minimum !== group.minimum;
      });
    if (changed) {
      this.preserve(() => {
        for (const host of this.sides.keys()) if (!groups.has(host)) this.clearSide(host);
        for (const [host, group] of groups) {
          host.classList.add("flow-annotation-side");
          host.style.setProperty("--flow-side-width", `${group.width}px`);
          host.style.setProperty("--flow-side-height", `${group.minimum}px`);
        }
        this.sides = groups;
      });
      this.changed();
      this.schedule();
    }
    // The caller places notes against the updated host bounds in this pass.
    return groups;
  }

  connect(host, group) {
    const previous = this.sides.get(host);
    let lines = previous?.lines;
    if (!lines) {
      lines = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      lines.classList.add("flow-side-lines");
      lines.setAttribute("fill", "none");
      lines.setAttribute("aria-hidden", "true");
      lines.setAttribute("focusable", "false");
      host.after(lines);
    }
    group.lines = lines;
    if (previous) previous.lines = lines;
    const bounds = host.getBoundingClientRect();
    this.place(lines, bounds.left, bounds.top);
    const width = bounds.width,
      height = bounds.height,
      divider = width - group.width;
    lines.style.width = `${width}px`;
    lines.style.height = `${height}px`;
    const local = (rect) => ({
      left: rect.left - bounds.left,
      right: rect.right - bounds.left,
      top: rect.top - bounds.top,
      bottom: rect.bottom - bounds.top,
    });
    const ink = inkRectangles(host).map(local);
    const targets = group.records.map((record) => ({
      record,
      target: this.rectangles(record).at(-1),
      note: record.body.getBoundingClientRect(),
    }));
    const key = JSON.stringify(
      [
        width,
        height,
        divider,
        ink,
        targets.map(({ record, target, note }) => [
          record.note.id,
          target && local(target),
          local(note),
        ]),
      ],
      (_, value) => (typeof value === "number" ? Math.round(value * 4) / 4 : value),
    );
    if (lines.flowSideGeometry === key) return;
    lines.flowSideGeometry = key;
    let svg = `<path class="flow-side-divider" d="M${divider},0 V${height}"/>`;
    for (const { record, target, note } of targets) {
      if (!target) continue;
      const end = { x: divider, y: Math.max(4, note.top - bounds.top - 4) };
      const obstacles = ink.concat([
        { left: 0, right: width, top: -1000, bottom: 0 },
        { left: 0, right: width, top: height, bottom: height + 1000 },
      ]);
      let route, point;
      for (const [x, y, anchor] of [
        [target.right + 2, target.top - 4, "north"],
        [(target.left + target.right) / 2, target.top - 4, "north"],
        [target.right + 4, (target.top + target.bottom) / 2, "east"],
        [(target.left + target.right) / 2, target.bottom + 4, "south"],
      ]) {
        point = {
          x: Math.max(4, Math.min(divider - 8, x - bounds.left)),
          y: Math.max(4, Math.min(height - 4, y - bounds.top)),
        };
        route = routeConnection(
          {
            kind: "line",
            points: [point, { x: divider - 8, y: point.y }, { x: divider - 8, y: end.y }, end],
            start: { anchor },
            end: { anchor: "west" },
          },
          obstacles,
          width,
          height,
          parseFloat(getComputedStyle(host).fontSize),
        );
        if (route) break;
      }
      if (!route) continue;
      const path = route.points.map((p, i) => `${i ? "L" : "M"}${p.x},${p.y}`).join(" ");
      svg +=
        `<path class="flow-side-connector" data-note="${record.note.id}" d="${path}"/>` +
        `<circle class="flow-side-dot" cx="${point.x}" cy="${point.y}" r="2.5"/>`;
    }
    if (lines.flowSidePaint !== svg) {
      lines.innerHTML = svg;
      lines.flowSidePaint = svg;
    }
  }

  layout() {
    const selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    const area = this.article.getBoundingClientRect();
    const fontSize = parseFloat(getComputedStyle(this.article).fontSize);
    const side = sideAnnotations({
      width: document.documentElement.clientWidth,
      height: innerHeight,
      articleWidth:
        area.width -
        parseFloat(getComputedStyle(this.article).paddingLeft) -
        parseFloat(getComputedStyle(this.article).paddingRight),
      fontSize,
    });
    const layout = side ? "side" : "compact";
    const geometry = `${area.width}:${fontSize}:${layout}`;
    if (this.geometry !== geometry) {
      this.geometry = geometry;
      if (this.reserved.size) {
        this.preserve(() => {
          for (const host of this.reserved.keys())
            host.style.removeProperty("--flow-annotation-padding");
          this.reserved.clear();
        });
        this.changed();
        this.schedule();
        return;
      }
    }
    if (this.article.dataset.annotationLayout !== layout) {
      this.preserve(() => {
        this.article.dataset.annotationLayout = layout;
      });
      this.changed();
    }
    const groups = this.sideGroups(side, fontSize);
    const sideRecords = new Set();
    for (const [host, group] of groups) {
      const bounds = host.getBoundingClientRect();
      const target = this.rectangles(group.records[0])[0];
      let top = Math.max(
        bounds.top + group.top,
        Math.min(target?.top ?? bounds.top, bounds.bottom - group.bottom - group.height),
      );
      for (const record of group.records) {
        sideRecords.add(record);
        this.place(record.note, bounds.right - group.width, top);
        top += record.note.getBoundingClientRect().height + 16;
      }
      this.connect(host, group);
    }
    const labels = [];
    const spacing = new Map();
    for (const record of this.records.values()) {
      const { note } = record;
      if (note.classList.contains("flow-unresolved") || !record.nodes.length) continue;
      if (sideRecords.has(record)) continue;
      if (record.kind === "footnote") {
        this.mode(record, "endnote");
        continue;
      }
      const rects = this.rectangles(record);
      if (!rects.length) {
        if (this.active === record) this.close();
        this.mode(record, "popover");
        continue;
      }
      const target = rects[0];
      if (
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
        const hostBounds = host?.getBoundingClientRect();
        const ink = [
          ...(host?.querySelectorAll(
            "mjx-c,mjx-utext,mjx-stretchy-h,mjx-stretchy-v,mi,mn,mo,mtext",
          ) ?? []),
        ]
          .filter(painted)
          .flatMap((node) => [...node.getClientRects()])
          .filter((rect) => rect.width > 0 && rect.height > 0);
        if (host?.matches("p")) {
          const text = document.createTreeWalker(host, NodeFilter.SHOW_TEXT);
          for (let node = text.nextNode(); node; node = text.nextNode()) {
            if (
              !node.data.trim() ||
              node.parentElement.closest(
                "math,.flow-math-view,.flow-note,svg,.flow-math-status,.flow-decoration-notice",
              )
            )
              continue;
            const range = document.createRange();
            range.selectNodeContents(node);
            ink.push(...range.getClientRects());
          }
        }
        const fits =
          host &&
          note.scrollWidth <= note.clientWidth + 1 &&
          size.width <=
            Math.min(area.right, hostBounds.right) - Math.max(area.left, hostBounds.left) - 8;
        const box = fits
          ? labelPosition(
              anchor,
              size,
              {
                left: Math.max(area.left, hostBounds.left) + 4,
                right: Math.min(area.right, hostBounds.right) - 4,
                top: hostBounds.top + 3,
              },
              [...ink, ...labels],
            )
          : null;
        if (
          !box &&
          fits &&
          !host.querySelector('.flow-math-view[data-math-state="pending"]') &&
          !note.querySelector('.flow-math-view[data-math-state="pending"]')
        ) {
          const count = [...this.records.values()].filter(
            (other) =>
              other.short && this.fragments(other)[0]?.closest(".flow-equation,p") === host,
          ).length;
          const rows = this.reserved.get(host) ?? 0;
          if (rows < count)
            spacing.set(host, {
              rows: rows + 1,
              padding: parseFloat(getComputedStyle(host).paddingTop) + size.height + 9,
            });
        }
        if (!box) this.mode(record, "popover");
        else {
          this.place(note, box.left, box.top);
          labels.push(box);
        }
      } else this.mode(record, "popover");
    }
    if (spacing.size) {
      this.preserve(() => {
        for (const [host, { rows, padding }] of spacing) {
          this.reserved.set(host, rows);
          host.style.setProperty("--flow-annotation-padding", `${padding}px`);
        }
      });
      this.changed();
      this.schedule();
      return;
    }
    for (const record of this.records.values()) {
      if (record.kind === "footnote") continue;
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
