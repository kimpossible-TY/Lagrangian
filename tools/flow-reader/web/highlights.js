// Explicit source highlights, Codex context and browser-local review strikes.
import { logicalTextIndex, selectedIntervals } from "./math-identity.js";
import { ReaderReviewMarks, sourceSegments } from "./review-marks.js";
const excluded = "svg,script,style,nav,.flow-notes,[data-flow-targets]";

export const textIndex = logicalTextIndex;

export class ReaderHighlights {
  constructor(article) {
    this.article = article;
    this.viewerID = crypto.getRandomValues(new Uint32Array(1))[0] + 1;
    this.action = document.querySelector("#reader-selection");
    this.message = document.querySelector("#reader-highlight-message");
    this.sourceButton = document.querySelector("#reader-source-highlight");
    this.saveButton = document.querySelector("#reader-codex-save");
    this.strikeButton = document.querySelector("#reader-strike");
    this.undoButton = document.querySelector("#reader-strike-undo");
    this.clearButton = document.querySelector("#reader-strike-clear");
    this.review = new ReaderReviewMarks(article, () => this.updateActions());
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
    this.repaint();
  }

  repaint() {
    this.review.schedule();
  }

  capture() {
    if (this.pressing) return;
    const selection = window.getSelection();
    if (
      !this.manifest ||
      !selection?.rangeCount ||
      selection.isCollapsed ||
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
          service: this.manifest.service,
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
    const pending = Boolean(this.pendingSource || this.pendingCodex);
    const codexTooLarge =
      fragments && [...fragments.map((part) => part.exact).join("\n")].length > 8000;
    this.sourceButton.disabled = Boolean(tooLarge || pending);
    this.saveButton.disabled = Boolean(tooLarge || codexTooLarge || pending);
    this.strikeButton.disabled = Boolean(tooLarge);
    this.sourceButton.hidden = !selected && !this.pendingSource;
    this.sourceButton.querySelector("span").textContent = this.pendingSource
      ? "적용 중…"
      : "하이라이트";
    this.undoButton.hidden = this.clearButton.hidden = !this.review.store.marks.length;
    document.querySelector("#reader-review-actions").hidden = !this.review.store.marks.length;
    document.querySelector("#reader-selection-actions").hidden = !selected && !this.pendingSource;
    document.querySelector("#reader-selection-cancel").hidden = !selected;
    this.action.hidden = !selected && !this.review.store.marks.length && !this.pendingSource;
    this.action.setAttribute("aria-busy", String(pending));
    const hint = document.querySelector("#reader-selection-hint");
    hint.classList.toggle("reader-visually-hidden", !tooLarge && !codexTooLarge);
    hint.textContent = tooLarge
      ? "구절을 조금 짧게 선택해 주세요."
      : codexTooLarge
        ? "Codex 저장은 8000자까지 가능합니다."
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
    Object.assign(this.action.style, {
      left: `${viewport.offsetLeft + viewport.width / 2}px`,
      bottom: "auto",
      maxWidth: `${Math.max(0, viewport.width - 32)}px`,
    });
    const top = Math.max(
      viewport.offsetTop + 8,
      bottom - this.action.getBoundingClientRect().height,
    );
    this.action.style.top = `${top}px`;
    Object.assign(this.message.style, {
      top: `${Math.max(viewport.offsetTop + 8, (this.action.hidden ? bottom : top - 8) - this.message.getBoundingClientRect().height)}px`,
      bottom: "auto",
    });
  }

  collapse() {
    if (this.pendingSource) this.pendingDismissed = true;
    if (this.pendingCodex) this.pendingCodexDismissed = true;
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
        body: JSON.stringify({
          revision,
          fragments: selected,
        }),
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
            ? "소스 범위를 정확히 연결할 수 없습니다. Codex 저장을 사용할 수 있습니다."
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

  async save(selected = this.selection) {
    if (
      !selected ||
      !this.manifest ||
      this.pendingSource ||
      this.pendingCodex ||
      this.saveButton.disabled
    )
      return;
    const revision = this.manifest.revision;
    this.pendingCodex = selected;
    this.pendingCodexDismissed = false;
    this.updateActions();
    this.announce("Codex용 텍스트 저장 중…");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch("api/focus", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          revision,
          fragments: selected,
          service: selected[0].service,
          viewerID: this.viewerID,
        }),
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(`Codex context HTTP ${response.status}`);
      const result = await response.json();
      const same =
        !this.pendingCodexDismissed &&
        this.manifest.revision === revision &&
        this.selection &&
        JSON.stringify(this.selection) === JSON.stringify(selected);
      if (
        ["selected", "unmapped"].includes(result.status) &&
        result.rendered_revision === revision
      ) {
        if (same) this.collapse();
        this.announce(
          result.source
            ? `Codex용 텍스트 저장됨 · ${result.source.filepath.split(/[\\/]/).pop()}:${result.source.line}`
            : "Codex용 텍스트 저장됨 · 소스 연결 없음",
        );
      } else if (result.status === "stale") {
        if (same) this.collapse();
        this.announce("문서나 Reader 연결이 변경되었습니다. 갱신 후 다시 선택해 주세요.");
      } else {
        throw new Error("Invalid Codex context response");
      }
    } catch {
      if (
        !this.pendingCodexDismissed &&
        this.manifest.revision === revision &&
        (!this.selection || JSON.stringify(this.selection) === JSON.stringify(selected))
      ) {
        this.selection = this.retainedSelection = selected;
      }
      this.announce("Codex용 텍스트를 저장하지 못했습니다. 연결 후 다시 시도해 주세요.");
    } finally {
      clearTimeout(timer);
      this.pendingCodex = null;
      this.updateActions();
    }
  }
}
