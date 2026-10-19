import { SelectionSubmission } from "../../reader-common/selection/submission.js";

/** Verified source edits; the selection adapter owns DOM capture and feedback. */
export class SourceHighlightController {
  constructor(view, transport) {
    this.view = view;
    this.transport = transport;
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
    const canApply = () =>
      this.submission.canApply(ticket, view.selection(), view.document()?.revision);
    view.changed();
    view.announce("하이라이트를 소스에 적용하는 중…");
    try {
      const result = await this.transport.post(
        "api/highlight",
        { revision, fragments: selected },
        120000,
      );
      if (["highlighted", "stale"].includes(result.status)) {
        if (canApply()) view.collapse();
        view.announce(
          result.status === "highlighted"
            ? "소스에 하이라이트를 저장했습니다. 문서를 갱신하는 중…"
            : "문서가 변경되었습니다. 다시 선택해 주세요.",
        );
      } else {
        if (canApply()) view.retain(selected);
        view.announce(
          ["unmapped", "unsupported"].includes(result.status)
            ? "소스 범위를 정확히 연결할 수 없습니다. Codex 저장을 사용할 수 있습니다."
            : "하이라이트를 저장하지 못했습니다. 다시 시도해 주세요.",
        );
      }
    } catch {
      if (canApply()) view.retain(selected);
      view.announce("하이라이트를 저장하지 못했습니다. 연결 후 다시 시도해 주세요.");
    } finally {
      this.submission.finish(ticket);
      view.changed();
    }
  }
}
