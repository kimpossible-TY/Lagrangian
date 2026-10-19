// Explicit source highlights, Codex context and browser-local review strikes.
import { ReaderReviewMarks } from "../review-strikes/renderer.js";
import { selectedReaderText } from "./dom-selection.js";
import { SourceHighlightController } from "../source-highlight/controller.js";
import { CodexContextController } from "../codex-context/controller.js";
import { ReaderTransport } from "../session/transport.js";
export { textIndex } from "./dom-selection.js";

export class ReaderSelectionActions {
  constructor(article) {
    this.article = article;
    this.listeners = [];
    const listen = (target, type, listener) => {
      if (!target) return;
      target.addEventListener(type, listener);
      this.listeners.push(() => target.removeEventListener(type, listener));
    };
    this.viewerID = crypto.getRandomValues(new Uint32Array(1))[0] + 1;
    this.action = document.querySelector("#reader-selection");
    this.message = document.querySelector("#reader-highlight-message");
    this.sourceButton = document.querySelector("#reader-source-highlight");
    this.saveButton = document.querySelector("#reader-codex-save");
    this.strikeButton = document.querySelector("#reader-strike");
    this.undoButton = document.querySelector("#reader-strike-undo");
    this.clearButton = document.querySelector("#reader-strike-clear");
    this.review = new ReaderReviewMarks(article, () => this.updateActions());
    const view = {
      document: () => this.manifest,
      selection: () => this.selection,
      sameSelection: (left, right) => JSON.stringify(left) === JSON.stringify(right),
      enabled: (action) => !(action === "save" ? this.saveButton : this.sourceButton).disabled,
      collapse: () => this.collapse(),
      retain: (selected) => {
        this.selection = this.retainedSelection = selected;
      },
      announce: (text) => this.announce(text),
      changed: () => this.updateActions(),
    };
    const transport = (this.transport = new ReaderTransport());
    this.source = new SourceHighlightController(view, transport);
    this.codex = new CodexContextController(view, transport, this.viewerID);
    const action = (button, perform) => {
      listen(button, "pointerdown", (event) => {
        this.pressing = true;
        this.pressedSelection = this.selection;
        event.preventDefault();
      });
      listen(button, "mousedown", (event) => event.preventDefault());
      for (const type of ["pointerup", "pointercancel"])
        listen(button, type, () => {
          clearTimeout(this.pressTimer);
          this.pressTimer = setTimeout(() => {
            this.pressing = false;
            this.pressedSelection = null;
          }, 0);
        });
      listen(button, "click", () => {
        const selected = this.pressedSelection ?? this.selection;
        this.pressing = false;
        this.pressedSelection = null;
        perform(selected);
        this.updateActions();
      });
    };
    action(this.saveButton, (selected) => this.codex.submit(selected));
    action(this.sourceButton, (selected) => this.source.submit(selected));
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
    listen(document.querySelector("#reader-selection-cancel"), "click", () => {
      this.collapse();
    });
    listen(window, "resize", () => this.position());
    listen(window.visualViewport, "resize", () => this.position());
    listen(window.visualViewport, "scroll", () => this.position());
    listen(document, "selectionchange", () => {
      clearTimeout(this.selectionTimer);
      this.selectionTimer = setTimeout(() => this.capture(), 80);
    });
  }

  announce(text) {
    if (this.disposed) return;
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
        !this.source.pending &&
        !this.retainedSelection
      ) {
        this.selection = null;
      }
      this.updateActions();
      return;
    }
    this.selection = selectedReaderText(this.article, this.manifest, selection);
    this.retainedSelection = null;
    this.updateActions();
  }

  updateActions() {
    if (this.disposed) return;
    const fragments = this.selection;
    const tooLarge =
      fragments &&
      (fragments.length > 32 ||
        fragments.reduce((size, part) => size + part.exact.length, 0) > 20000);
    const selected = Boolean(fragments);
    for (const button of [this.saveButton, this.sourceButton, this.strikeButton])
      button.hidden = !selected;
    const pending = Boolean(this.source.pending || this.codex.pending);
    const codexTooLarge =
      fragments && [...fragments.map((part) => part.exact).join("\n")].length > 8000;
    this.sourceButton.disabled = Boolean(tooLarge || pending);
    this.saveButton.disabled = Boolean(tooLarge || codexTooLarge || pending);
    this.strikeButton.disabled = Boolean(tooLarge);
    this.sourceButton.hidden = !selected && !this.source.pending;
    this.sourceButton.querySelector("span").textContent = this.source.pending
      ? "적용 중…"
      : "하이라이트";
    this.undoButton.hidden = this.clearButton.hidden = !this.review.store.marks.length;
    document.querySelector("#reader-review-actions").hidden = !this.review.store.marks.length;
    document.querySelector("#reader-selection-actions").hidden = !selected && !this.source.pending;
    document.querySelector("#reader-selection-cancel").hidden = !selected;
    this.action.hidden = !selected && !this.review.store.marks.length && !this.source.pending;
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
    this.source.dismiss();
    this.codex.dismiss();
    this.selection = this.retainedSelection = null;
    window.getSelection()?.removeAllRanges();
    this.updateActions();
  }
  dispose() {
    this.disposed = true;
    this.source.dismiss();
    this.codex.dismiss();
    this.transport.dispose();
    this.review.dispose();
    for (const remove of this.listeners) remove();
    for (const timer of [this.pressTimer, this.selectionTimer, this.messageTimer])
      clearTimeout(timer);
  }
}
