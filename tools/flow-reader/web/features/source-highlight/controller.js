import { SelectionSubmission } from "../../reader-common/selection/submission.js";

export const sourceHighlightSnapshot = (document) =>
  JSON.stringify([document?.documentID, document?.revision, document?.service]);

/** Verified source edits; the selection adapter owns DOM capture and feedback. */
export class SourceHighlightController {
  constructor(view, transport, highlights, intents = null) {
    this.view = view;
    this.transport = transport;
    this.highlights = highlights;
    this.intents = intents;
    this.submission = new SelectionSubmission(view.sameSelection);
  }

  get pending() {
    return Boolean(this.submission.pending);
  }

  dismiss() {
    this.submission.dismiss();
  }

  async submit(selected) {
    const view = this.view;
    const document = view.document();
    if (!selected || !document || !view.enabled("highlight")) return;
    const revision = document.revision;
    if (selected.some((part) => part.revision !== revision)) {
      if (view.selection() === selected) view.collapse();
      view.announce("문서가 변경되었습니다. 다시 선택해 주세요.");
      return;
    }
    const ticket = this.submission.begin(selected, revision);
    if (!ticket) return;
    const snapshot = sourceHighlightSnapshot(document);
    const canApply = () =>
      snapshot === sourceHighlightSnapshot(view.document()) &&
      this.submission.canApply(ticket, view.selection(), view.document()?.revision);
    this.highlights.begin(ticket, snapshot);
    view.releaseSelection();
    view.changed();
    view.announce("하이라이트를 소스에 적용하는 중…");
    try {
      const editorServer = view.editorServer?.();
      const editorAttachment = view.editorAttachment?.();
      const payload = {
        revision,
        fragments: selected,
        ...(editorServer ? { editorServer } : {}),
        ...(editorAttachment ? { editorAttachment } : {}),
      };
      const result = this.intents
        ? await this.intents.submit({
            ...payload,
            documentID: document.documentID,
            service: selected[0]?.service ?? document.service,
          })
        : await this.transport.post("api/highlight", payload, 120000);
      this.highlights.settle(ticket, result.status);
      if (result.status === "queued") {
        if (canApply()) view.collapse();
        view.announce(
          "하이라이트 요청을 이 기기에 보관했습니다. 연결되면 원본을 확인한 뒤 저장합니다.",
        );
      } else if (["highlighted", "stale"].includes(result.status)) {
        if (canApply()) view.collapse();
        view.announce(
          result.status === "highlighted"
            ? "소스에 하이라이트를 저장했습니다. 문서를 갱신하는 중…"
            : "문서가 변경되었습니다. 다시 선택해 주세요.",
        );
      } else {
        if (canApply()) view.retain(selected);
        view.announce(
          result.status === "uncertain"
            ? "이전 요청의 저장 여부를 확인할 수 없습니다. 원본을 확인한 뒤 다시 선택해 주세요."
            : result.status === "editor-mismatch"
              ? "Reader와 Neovim 연결이 변경되었습니다. Reader 패널을 다시 열어 주세요."
              : result.status === "modified"
                ? "Neovim에 저장하지 않은 변경 사항이 있습니다. 먼저 저장한 뒤 다시 선택해 주세요."
                : ["unmapped", "unsupported"].includes(result.status)
                  ? "소스 범위를 정확히 연결할 수 없습니다. Codex 저장을 사용할 수 있습니다."
                  : "하이라이트를 저장하지 못했습니다. 다시 시도해 주세요.",
        );
      }
    } catch {
      this.highlights.settle(ticket, "error");
      if (canApply()) view.retain(selected);
      view.announce(
        this.intents
          ? "하이라이트 요청을 보관하지 못했습니다. 저장 공간과 대기 요청 수를 확인해 주세요."
          : "하이라이트를 저장하지 못했습니다. 연결 후 다시 시도해 주세요.",
      );
    } finally {
      this.submission.finish(ticket);
      view.changed();
    }
  }
}
