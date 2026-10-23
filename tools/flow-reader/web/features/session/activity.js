import { ActivityNotice, activityPhase } from "../../reader-common/session/activity.js";
import { uiLanguage } from "../../ui/language.js";

/** HTTP publication and section loading belong to the HTML session. */
export class ReaderActivityState {
  constructor() {
    this.server = null;
    this.connected = true;
    this.renderedRevision = null;
    this.renderedDocumentID = null;
    this.sequence = 0;
    this.request = null;
    this.failed = false;
  }

  phase(held = null) {
    const compiler = this.server?.compiling
      ? "compiling"
      : this.server?.exitCode ||
          (this.server?.contentGatePassed === false && !this.server.development)
        ? "error"
        : "success";
    return activityPhase({
      connection: this.connected ? "connected" : "reconnecting",
      error: this.failed ? "load-error" : null,
      compiler,
      pending:
        this.request?.phase ??
        (this.server?.revision &&
        (this.server.revision !== this.renderedRevision ||
          this.server.documentID !== this.renderedDocumentID)
          ? (held ?? "loading")
          : null),
      rendered: Boolean(this.renderedRevision),
    });
  }

  update(server) {
    this.server = server;
    this.connected = true;
  }

  begin(sequence, revision) {
    this.sequence = sequence;
    this.request = { revision, documentID: this.server?.documentID, phase: "loading" };
    this.failed = false;
  }

  mounting(sequence) {
    if (sequence === this.sequence && this.request) this.request.phase = "rendering";
  }

  cancel(sequence) {
    if (sequence !== this.sequence) return;
    // Local navigation can supersede the scroll callback after synchronous
    // mounting. That content is already present; a cancelled fetch is not.
    if (this.request?.phase === "rendering") {
      this.renderedRevision = this.request.revision;
      this.renderedDocumentID = this.request.documentID;
    }
    this.request = null;
  }

  rendered(sequence) {
    if (sequence !== this.sequence || !this.request) return;
    this.renderedRevision = this.request.revision;
    this.renderedDocumentID = this.request.documentID;
    this.request = null;
  }

  error(sequence) {
    if (sequence !== this.sequence) return;
    this.request = null;
    this.failed = true;
  }
}

/** HTML signals and interaction events adapt the paged reader's shared notice. */
export class ReaderActivity {
  constructor(element, adapter) {
    this.state = new ReaderActivityState();
    this.notice = new ActivityNotice(element, {
      phase: () => this.state.phase(adapter.held()),
      language: uiLanguage(),
      topOffset: 52,
      hasSelection: adapter.hasSelection,
      releaseSelection: adapter.releaseSelection,
      resume: adapter.resume,
      hint: (phase) =>
        phase.endsWith("error") || phase === "reconnecting"
          ? this.state.renderedRevision
            ? "현재 문서는 계속 읽을 수 있습니다."
            : "소스와 서버 상태를 확인해 주세요."
          : null,
    });
    this.interactionChanged = () => {
      this.refresh();
      adapter.resume();
    };
    for (const event of ["selectionchange", "close", "toggle", "touchend", "touchcancel"])
      document.addEventListener(event, this.interactionChanged, true);
  }

  refresh() {
    this.notice.refresh();
  }

  dispose() {
    for (const event of ["selectionchange", "close", "toggle", "touchend", "touchcancel"])
      document.removeEventListener(event, this.interactionChanged, true);
    this.notice.dispose();
  }
}
