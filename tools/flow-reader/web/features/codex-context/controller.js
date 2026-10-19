import { SelectionSubmission } from "../../reader-common/selection/submission.js";

/** Explicitly records one selected context through the Reader's focus contract. */
export class CodexContextController {
  constructor(view, transport, viewerID) {
    this.view = view;
    this.transport = transport;
    this.viewerID = viewerID;
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
    if (!selected || !document || !view.enabled("save")) return;
    const revision = document.revision;
    const ticket = this.submission.begin(selected, revision);
    if (!ticket) return;
    const canApply = (allowCollapsed = true) =>
      this.submission.canApply(ticket, view.selection(), view.document()?.revision, allowCollapsed);
    view.changed();
    view.announce("Codex용 텍스트 저장 중…");
    try {
      const result = await this.transport.post(
        "api/focus",
        {
          revision,
          fragments: selected,
          service: selected[0].service,
          viewerID: this.viewerID,
        },
        15000,
      );
      if (
        ["selected", "unmapped"].includes(result.status) &&
        result.rendered_revision === revision
      ) {
        if (canApply(false)) view.collapse();
        view.announce(
          result.source
            ? `Codex용 텍스트 저장됨 · ${result.source.filepath.split(/[\\/]/).pop()}:${result.source.line}`
            : "Codex용 텍스트 저장됨 · 소스 연결 없음",
        );
      } else if (result.status === "stale") {
        if (canApply(false)) view.collapse();
        view.announce("문서나 Reader 연결이 변경되었습니다. 갱신 후 다시 선택해 주세요.");
      } else {
        throw new Error("Invalid Codex context response");
      }
    } catch {
      if (canApply()) view.retain(selected);
      view.announce("Codex용 텍스트를 저장하지 못했습니다. 연결 후 다시 시도해 주세요.");
    } finally {
      this.submission.finish(ticket);
      view.changed();
    }
  }
}
