import { focusStatusPlacement } from "./mobile-viewport";
import { ReviewMarkRenderer } from "../review-strikes/renderer";
import { SourceHighlightRenderer } from "../source-highlight/renderer";
import { SelectionSubmission } from "../../../../reader-common/selection/submission.js";
import { SelectionPress } from "../../../../reader-common/selection/press.js";
import { selectedPreviewText, type SelectedText } from "./text-selection";

export class SelectionActions {
  private toolbar = document.createElement("div");
  private selection?: SelectedText;
  private retainedSelection?: SelectedText;
  private press = new SelectionPress<SelectedText>(() => this.updateButtons());
  private highlight = new SelectionSubmission<SelectedText>(
    (current, submitted) =>
      current.revision === submitted.revision &&
      current.text === submitted.text &&
      current.start.page_no === submitted.start.page_no &&
      current.start.x === submitted.start.x &&
      current.start.y === submitted.start.y &&
      current.end.page_no === submitted.end.page_no &&
      current.end.x === submitted.end.x &&
      current.end.y === submitted.end.y,
  );
  private review: ReviewMarkRenderer;
  private sourcePaint: SourceHighlightRenderer;
  private documentID = "";
  private saveButton: HTMLButtonElement;
  private highlightButton: HTMLButtonElement;
  private strikeButton: HTMLButtonElement;
  private undoButton: HTMLButtonElement;
  private clearButton: HTMLButtonElement;
  private enabled = false;
  private disposed = false;
  private frame?: number;
  private korean = navigator.language.startsWith("ko");

  constructor(
    private root: HTMLElement,
    private onAction: (action: "save" | "highlight", selection: SelectedText) => boolean,
    private readRevision: () => string | undefined,
  ) {
    this.review = new ReviewMarkRenderer(root);
    this.sourcePaint = new SourceHighlightRenderer(root);
    this.toolbar.className = "typst-selection-actions";
    this.toolbar.setAttribute("role", "toolbar");
    this.toolbar.setAttribute("aria-label", this.korean ? "선택한 텍스트" : "Selected text");
    this.toolbar.hidden = true;
    document.body.appendChild(this.toolbar);
    const button = (ko: string, en: string, action: (selected?: SelectedText) => void) => {
      const element = document.createElement("button");
      element.type = "button";
      element.textContent = this.korean ? ko : en;
      element.addEventListener("pointerdown", (event) => {
        this.press.begin(this.selection);
        event.preventDefault();
      });
      element.addEventListener("mousedown", (event) => event.preventDefault());
      const release = () => this.press.release();
      element.addEventListener("pointerup", release);
      element.addEventListener("pointercancel", release);
      element.addEventListener("click", () => {
        action(this.press.consume(this.selection) ?? undefined);
        this.updateButtons();
      });
      this.toolbar.appendChild(element);
      return element;
    };
    this.highlightButton = button("하이라이트", "Highlight", (selected) => {
      if (!selected || this.highlight.pending || !this.onAction("highlight", selected)) return;
      const ticket = this.highlight.begin(selected, selected.revision);
      if (!ticket) return;
      this.sourcePaint.highlights.begin(ticket, this.snapshot(selected.revision));
      // Release native selection so it cannot hold the compiled replacement.
      document.getSelection()?.removeAllRanges();
    });
    this.saveButton = button("Codex 저장", "Save for Codex", (selected) => {
      if (selected) this.onAction("save", selected);
    });
    this.strikeButton = button("빨간 취소선", "Red strike", (selected) => {
      if (!selected) return;
      this.review.store.add(selected);
      this.collapse();
      this.refresh();
    });
    this.strikeButton.className = "typst-strike-action";
    this.undoButton = button("되돌리기", "Undo", () => {
      this.review.store.undo();
      this.refresh();
    });
    this.clearButton = button("표시 지우기", "Clear marks", () => {
      this.review.store.clear();
      this.refresh();
    });
    document.addEventListener("selectionchange", this.selectionChanged);
    root.addEventListener("typst-text-layout", this.refresh);
    window.addEventListener("resize", this.position);
    window.visualViewport?.addEventListener("resize", this.position);
    window.visualViewport?.addEventListener("scroll", this.position);
    this.selectionChanged();
  }

  setEnabled(enabled: boolean) {
    this.enabled = enabled;
    this.updateButtons();
  }

  connectionLost() {
    // A failed connection has no deliverable acknowledgment. Do not replay a
    // source mutation, or leave every future selection blocked by its ticket.
    const ticket = this.highlight.pending;
    if (ticket) {
      this.sourcePaint.highlights.settle(ticket, "error");
      if (this.highlight.canApply(ticket, this.selection, this.readRevision()))
        this.selection = this.retainedSelection = this.selection ?? ticket.selection;
      this.highlight.finish(ticket);
    }
    this.enabled = false;
    this.updateButtons();
  }

  highlightFinished(status: string) {
    const ticket = this.highlight.pending;
    if (!ticket) return;
    this.sourcePaint.highlights.settle(ticket, status);
    if (this.highlight.canApply(ticket, this.selection, this.readRevision())) {
      if (status === "highlighted" || status === "stale") this.collapse();
      else this.selection = this.retainedSelection = this.selection ?? ticket.selection;
    }
    this.highlight.finish(ticket);
    this.updateButtons();
  }
  private snapshot(revision = this.readRevision()) {
    return JSON.stringify([this.documentID, revision]);
  }

  setDocument(id: string, revision = this.readRevision()) {
    if (id !== this.documentID || this.retainedSelection?.revision !== revision) {
      if (this.selection === this.retainedSelection) this.selection = undefined;
      this.retainedSelection = undefined;
    }
    this.documentID = id;
    this.sourcePaint.highlights.onDocument(this.snapshot(revision));
    this.review.store.setDocument(id);
    this.afterRender();
  }
  afterRender() {
    if (this.frame !== undefined) cancelAnimationFrame(this.frame);
    this.frame = requestAnimationFrame(() => {
      this.frame = undefined;
      if (!this.disposed) this.refresh();
    });
  }

  private selectionChanged = () => {
    const selected = selectedPreviewText(this.root);
    if (selected) {
      selected.revision = this.readRevision();
      this.retainedSelection = undefined;
    }
    this.selection = selected ?? this.retainedSelection;
    this.updateButtons();
  };

  private collapse() {
    document.getSelection()?.removeAllRanges();
    this.selection = undefined;
    this.retainedSelection = undefined;
    this.updateButtons();
  }

  private updateButtons() {
    if (this.press.active) return;
    const selected = !!this.selection;
    this.highlightButton.hidden = this.saveButton.hidden = this.strikeButton.hidden = !selected;
    const ready =
      this.enabled && !!this.selection?.revision && this.selection.revision === this.readRevision();
    this.saveButton.disabled = this.highlightButton.disabled = !ready || !!this.highlight.pending;
    this.undoButton.hidden = this.clearButton.hidden = !this.review.store.marks.length;
    this.toolbar.hidden = !selected && !this.review.store.marks.length;
    this.position();
  }

  position = () => {
    const viewport = window.visualViewport;
    if (!viewport) return;
    const style = getComputedStyle(document.documentElement);
    const inset = (edge: string) =>
      Number.parseFloat(style.getPropertyValue(`--preview-safe-${edge}`)) || 0;
    const placement = focusStatusPlacement(viewport, {
      left: inset("left"),
      right: inset("right"),
      bottom: inset("bottom"),
    });
    // Leave room for status messages even when their text wraps onto more lines.
    const statusHeight =
      document.querySelector(".typst-focus-status")?.getBoundingClientRect().height || 0;
    placement.top = `${Number.parseFloat(placement.top) - statusHeight - 8 / (viewport.scale || 1)}px`;
    Object.assign(this.toolbar.style, placement);
  };

  private refresh = () => {
    if (this.disposed) return;
    this.review.repaint();
    this.sourcePaint.highlights.repaint();
    this.updateButtons();
  };

  dispose() {
    this.disposed = true;
    this.press.dispose();
    if (this.frame !== undefined) cancelAnimationFrame(this.frame);
    document.removeEventListener("selectionchange", this.selectionChanged);
    this.root.removeEventListener("typst-text-layout", this.refresh);
    window.removeEventListener("resize", this.position);
    window.visualViewport?.removeEventListener("resize", this.position);
    window.visualViewport?.removeEventListener("scroll", this.position);
    this.toolbar.remove();
    this.review.dispose();
    this.sourcePaint.dispose();
  }
}
