// Saved quotations stay local. Source highlights and review strikes are separate
// explicit actions; DOM ranges paint quotations without wrapping MathML.
import { logicalTextIndex, rangesFor, selectedIntervals } from "./math-identity.js";
import { ReaderReviewMarks, sourceSegments } from "./review-marks.js";
const excluded = "svg,script,style,nav,.flow-notes,[data-flow-targets]";

export const textIndex = logicalTextIndex;

export function occurrences(text, exact) {
  const result = [];
  for (let start = text.indexOf(exact); start >= 0; start = text.indexOf(exact, start + 1)) {
    result.push(start);
  }
  return result;
}

function validRecord(record) {
  return (
    typeof record?.id === "string" &&
    Array.isArray(record.fragments) &&
    record.fragments.length > 0 &&
    record.fragments.length <= 32 &&
    record.fragments.every(
      (part) =>
        typeof part.key === "string" &&
        part.key.length <= 128 &&
        typeof part.exact === "string" &&
        part.exact.length > 0 &&
        part.exact.length <= 20000 &&
        typeof part.prefix === "string" &&
        part.prefix.length <= 120 &&
        typeof part.suffix === "string" &&
        part.suffix.length <= 120,
    )
  );
}

export class ReaderHighlights {
  constructor(article, navigate, { beforeOpen = () => {}, returnFocus } = {}) {
    this.article = article;
    this.navigate = navigate;
    this.records = [];
    this.locations = new Map();
    this.sequence = 0;
    this.dialog = document.querySelector("#reader-highlights");
    this.list = document.querySelector("#reader-highlights-list");
    this.action = document.querySelector("#reader-selection");
    this.message = document.querySelector("#reader-highlight-message");
    this.button = document.querySelector("#reader-highlights-open");
    this.button.disabled = false;
    this.supportsPaint = typeof Highlight === "function" && Boolean(globalThis.CSS?.highlights);
    this.sourceButton = document.querySelector("#reader-source-highlight");
    this.saveButton = document.querySelector("#reader-highlight-save");
    this.strikeButton = document.querySelector("#reader-strike");
    this.undoButton = document.querySelector("#reader-strike-undo");
    this.clearButton = document.querySelector("#reader-strike-clear");
    this.review = new ReaderReviewMarks(article, () => this.updateActions());
    this.button.addEventListener("click", () => {
      this.updateList();
      beforeOpen();
      this.dialog.showModal();
    });
    this.dialog.addEventListener("close", () => {
      if (!this.article.contains(document.activeElement))
        returnFocus?.focus({ preventScroll: true });
    });
    document
      .querySelector("#reader-highlights-close")
      .addEventListener("click", () => this.dialog.close());
    const action = (button, perform) => {
      button.addEventListener("pointerdown", (event) => {
        this.pressing = true;
        this.pressedSelection = this.selection;
        event.preventDefault();
      });
      button.addEventListener("mousedown", (event) => event.preventDefault());
      for (const type of ["pointerup", "pointercancel"])
        button.addEventListener(type, () => {
          clearTimeout(this.pressTimer);
          this.pressTimer = setTimeout(() => {
            this.pressing = false;
            this.pressedSelection = null;
          }, 0);
        });
      button.addEventListener("click", () => {
        const selected = this.pressedSelection ?? this.selection;
        this.pressing = false;
        this.pressedSelection = null;
        perform(selected);
        this.updateActions();
      });
    };
    action(this.saveButton, (selected) => this.save(selected));
    action(this.sourceButton, (selected) => this.highlightSource(selected));
    action(this.strikeButton, (selected) => {
      if (!selected || !this.review.add(selected)) return;
      this.collapse();
    });
    action(this.undoButton, () => {
      this.review.store.undo();
      this.review.repaint();
    });
    action(this.clearButton, () => {
      this.review.store.clear();
      this.review.repaint();
    });
    document.querySelector("#reader-selection-cancel").addEventListener("click", () => {
      this.collapse();
    });
    window.addEventListener("resize", () => this.position());
    window.visualViewport?.addEventListener("resize", () => this.position());
    window.visualViewport?.addEventListener("scroll", () => this.position());
    document.addEventListener("selectionchange", () => {
      clearTimeout(this.selectionTimer);
      this.selectionTimer = setTimeout(() => this.capture(), 80);
    });
    window.addEventListener("storage", (event) => {
      if (event.key === this.storageKey) {
        this.read();
        this.resolve();
      }
    });
  }

  announce(text) {
    clearTimeout(this.messageTimer);
    this.message.textContent = text;
    this.position();
    this.messageTimer = setTimeout(() => {
      this.message.textContent = "";
    }, 7000);
  }

  onDocument(manifest, section) {
    this.manifest = manifest;
    this.section = section;
    this.selection = null;
    this.retainedSelection = null;
    this.review.onDocument(manifest.documentID);
    this.updateActions();
    const storageKey = `flow-reader:${manifest.documentID}:highlights:v1`;
    if (storageKey !== this.storageKey) {
      this.storageKey = storageKey;
      this.read();
    }
    this.repaint();
    this.resolve();
  }

  read() {
    try {
      const value = JSON.parse(localStorage.getItem(this.storageKey));
      this.records = Array.isArray(value) ? value.filter(validRecord).slice(0, 200) : [];
    } catch {
      this.records = [];
    }
    this.locations.clear();
  }

  persist(records) {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(records));
      this.records = records;
      return true;
    } catch {
      this.announce("저장 공간을 사용할 수 없습니다. 표시를 저장하지 못했습니다.");
      return false;
    }
  }

  capture() {
    if (this.pressing) return;
    const selection = window.getSelection();
    if (
      !this.manifest ||
      !selection?.rangeCount ||
      selection.isCollapsed ||
      this.dialog.open ||
      document.querySelector("dialog[open]") ||
      !this.article.contains(selection.anchorNode) ||
      !this.article.contains(selection.focusNode)
    ) {
      if (
        !this.action.contains(document.activeElement) &&
        !this.pendingSource &&
        !this.retainedSelection
      ) {
        this.selection = null;
      }
      this.updateActions();
      return;
    }
    const range = selection.getRangeAt(0);
    const fragments = [];
    for (const block of this.article.querySelectorAll("[data-reader-key]")) {
      if (block.closest(excluded) || !range.intersectsNode(block)) continue;
      const index = textIndex(block);
      for (const [start, end] of selectedIntervals(index, range)) {
        fragments.push({
          key: block.dataset.readerKey,
          exact: index.text.slice(start, end),
          prefix: index.text.slice(Math.max(0, start - 64), start).trim(),
          suffix: index.text.slice(end, end + 64).trim(),
          start,
          end,
          revision: this.manifest.revision,
          segments: sourceSegments(index, start, end),
        });
      }
    }
    this.selection = fragments.length ? fragments : null;
    this.retainedSelection = null;
    this.updateActions();
  }

  updateActions() {
    const fragments = this.selection;
    const tooLarge =
      fragments &&
      (fragments.length > 32 ||
        fragments.reduce((size, part) => size + part.exact.length, 0) > 20000);
    const selected = Boolean(fragments);
    for (const button of [this.saveButton, this.sourceButton, this.strikeButton])
      button.hidden = !selected;
    this.saveButton.disabled = this.sourceButton.disabled = Boolean(tooLarge || this.pendingSource);
    this.strikeButton.disabled = Boolean(tooLarge);
    this.sourceButton.textContent = this.pendingSource ? "적용 중…" : "하이라이트";
    this.undoButton.hidden = this.clearButton.hidden = !this.review.store.marks.length;
    document.querySelector("#reader-selection-cancel").hidden = !selected;
    this.action.hidden = !selected && !this.review.store.marks.length && !this.pendingSource;
    this.action.setAttribute("aria-busy", String(Boolean(this.pendingSource)));
    document.querySelector("#reader-selection-hint").textContent = tooLarge
      ? "구절을 조금 짧게 선택해 주세요."
      : selected
        ? "선택한 구절"
        : "빨간 취소선";
    this.position();
  }

  position() {
    const viewport = window.visualViewport;
    if (!viewport) return;
    const safe =
      parseFloat(
        getComputedStyle(document.documentElement).getPropertyValue("--reader-safe-bottom"),
      ) || 0;
    const bottom = viewport.offsetTop + viewport.height - safe - 12;
    const top = bottom - this.action.getBoundingClientRect().height;
    Object.assign(this.action.style, {
      left: `${viewport.offsetLeft + viewport.width / 2}px`,
      top: `${Math.max(viewport.offsetTop + 8, top)}px`,
      bottom: "auto",
      maxWidth: `${Math.max(0, viewport.width - 16)}px`,
    });
    Object.assign(this.message.style, {
      top: `${Math.max(viewport.offsetTop + 8, (this.action.hidden ? bottom : top - 8) - this.message.getBoundingClientRect().height)}px`,
      bottom: "auto",
    });
  }

  collapse() {
    if (this.pendingSource) this.pendingDismissed = true;
    this.selection = this.retainedSelection = null;
    window.getSelection()?.removeAllRanges();
    this.updateActions();
  }

  async highlightSource(selected) {
    if (!selected || !this.manifest || this.pendingSource || this.sourceButton.disabled) return;
    const revision = this.manifest.revision;
    if (selected.some((part) => part.revision !== revision)) {
      if (this.selection === selected) this.collapse();
      this.announce("문서가 변경되었습니다. 다시 선택해 주세요.");
      return;
    }
    this.pendingSource = selected;
    this.pendingDismissed = false;
    this.updateActions();
    this.announce("하이라이트를 소스에 적용하는 중…");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 120000);
    try {
      const response = await fetch("api/highlight", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ revision, fragments: selected }),
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(`Highlight HTTP ${response.status}`);
      const result = await response.json();
      const same =
        this.manifest.revision === revision &&
        !this.pendingDismissed &&
        (!this.selection || JSON.stringify(this.selection) === JSON.stringify(selected));
      if (["highlighted", "stale"].includes(result.status)) {
        if (same) this.collapse();
        this.announce(
          result.status === "highlighted"
            ? "소스에 하이라이트를 저장했습니다. 문서를 갱신하는 중…"
            : "문서가 변경되었습니다. 다시 선택해 주세요.",
        );
      } else {
        if (same) this.selection = this.retainedSelection = selected;
        this.announce(
          ["unmapped", "unsupported"].includes(result.status)
            ? "소스 범위를 정확히 연결할 수 없습니다. 표시 저장을 사용할 수 있습니다."
            : "하이라이트를 저장하지 못했습니다. 다시 시도해 주세요.",
        );
      }
    } catch {
      if (
        this.manifest.revision === revision &&
        !this.pendingDismissed &&
        (!this.selection || JSON.stringify(this.selection) === JSON.stringify(selected))
      )
        this.selection = this.retainedSelection = selected;
      this.announce("하이라이트를 저장하지 못했습니다. 연결 후 다시 시도해 주세요.");
    } finally {
      clearTimeout(timer);
      this.pendingSource = null;
      this.updateActions();
    }
  }

  save(selected = this.selection) {
    if (!selected || !this.storageKey || this.pendingSource) return;
    if (this.records.length >= 200) {
      this.announce("표시는 200개까지 저장할 수 있습니다. 이전 표시를 지운 뒤 다시 시도해 주세요.");
      return;
    }
    const record = {
      id: globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
      createdAt: Date.now(),
      fragments: selected,
    };
    if (!validRecord(record) || !this.persist([...this.records, record])) return;
    this.collapse();
    this.announce("표시를 이 브라우저에 저장했습니다.");
    this.resolve();
  }

  async resolve() {
    if (!this.manifest) return;
    const sequence = ++this.sequence;
    this.resolveError = false;
    const revision = this.manifest.revision;
    const parts = this.records.flatMap((record) =>
      record.fragments.map((fragment, index) => ({
        key: `${record.id}:${index}`,
        fragment,
      })),
    );
    this.locations.clear();
    this.repaint();
    this.updateList();
    try {
      for (let offset = 0; offset < parts.length; ) {
        const batch = [];
        let bytes = 0;
        while (offset < parts.length && batch.length < 32) {
          const size = new TextEncoder().encode(JSON.stringify(parts[offset].fragment)).length;
          if (batch.length && bytes + size > 200000) break;
          bytes += size;
          batch.push(parts[offset++]);
        }
        const response = await fetch("api/locate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ revision, fragments: batch.map((part) => part.fragment) }),
        });
        if (!response.ok) throw new Error(`Passage HTTP ${response.status}`);
        const result = await response.json();
        if (sequence !== this.sequence || result.revision !== revision) return;
        if (!Array.isArray(result.locations) || result.locations.length !== batch.length)
          throw new Error("Invalid locations");
        batch.forEach((part, index) => this.locations.set(part.key, result.locations[index]));
      }
    } catch {
      if (sequence !== this.sequence) return;
      this.resolveError = true;
      this.announce("저장한 구절은 보관 중입니다. 연결 후 현재 위치를 다시 확인할 수 있습니다.");
    }
    if (sequence === this.sequence) {
      this.repaint();
      this.updateList();
    }
  }

  repaint() {
    const ranges = [];
    this.article
      .querySelectorAll(".reader-saved-block")
      .forEach((node) => node.classList.remove("reader-saved-block"));
    const nodes = new Map(
      [...this.article.querySelectorAll("[data-reader-key]")].map((node) => [
        node.dataset.readerKey,
        node,
      ]),
    );
    for (const record of this.records) {
      record.fragments.forEach((part, i) => {
        const location = this.locations.get(`${record.id}:${i}`);
        if (!location || location.state !== "located") return;
        const block = nodes.get(location.key);
        if (!block) return;
        const index = textIndex(block);
        const start = occurrences(index.text, part.exact)[location.occurrence];
        if (start === undefined) return;
        ranges.push(...rangesFor(index, start, start + part.exact.length));
        if (!this.supportsPaint) block.classList.add("reader-saved-block");
      });
    }
    if (this.supportsPaint) CSS.highlights.set("reader-saved", new Highlight(...ranges));
    this.review.schedule();
  }

  updateList() {
    this.button.textContent = `저장한 표시 ${this.records.length}개`;
    this.button.setAttribute("aria-label", `저장한 표시 ${this.records.length}개 보기`);
    this.list.replaceChildren();
    document.querySelector("#reader-highlights-empty").hidden = this.records.length > 0;
    for (const record of [...this.records].reverse()) {
      const row = document.createElement("li");
      const jump = document.createElement("button");
      jump.className = "reader-highlight-jump";
      const quote = document.createElement("span");
      quote.className = "reader-highlight-quote";
      quote.textContent = record.fragments.map((part) => part.exact).join("\n");
      const label = document.createElement("span");
      label.className = "reader-highlight-location";
      const locations = record.fragments.map((_, i) => this.locations.get(`${record.id}:${i}`));
      const location = locations.find((item) => item?.state === "located");
      const uncertain = locations.some((item) => item?.state !== "located");
      label.textContent = location
        ? uncertain
          ? "일부 구절의 위치를 찾았습니다 · 이동"
          : "본문으로 이동"
        : locations.some((item) => item?.state === "ambiguous")
          ? "같은 구절이 여러 곳에 있어 위치를 확인해야 합니다"
          : locations.some((item) => item?.state === "missing")
            ? "수정된 문서에서 찾지 못했습니다 · 원문은 보관 중"
            : this.resolveError
              ? "연결 후 현재 위치를 확인할 수 있습니다"
              : "현재 위치 확인 중";
      jump.disabled = !location;
      jump.append(quote, label);
      jump.addEventListener("click", async () => {
        this.dialog.close();
        window.getSelection()?.removeAllRanges();
        await this.navigate(location.id);
      });
      const remove = document.createElement("button");
      remove.textContent = "삭제";
      remove.setAttribute("aria-label", `${record.fragments[0].exact.slice(0, 30)} 표시 삭제`);
      remove.addEventListener("click", () => {
        if (this.persist(this.records.filter((item) => item.id !== record.id))) this.resolve();
      });
      row.append(jump, remove);
      this.list.append(row);
    }
  }
}
