import { hasTouchSelection } from "typst-dom/touch-selection.mjs";
import {
  ActivityNotice,
  activityPhase,
  type ActivityPhase,
} from "../../../../reader-common/session/activity.js";

export { activityPlacement } from "../../../../reader-common/session/activity.js";
export type { ActivityPhase } from "../../../../reader-common/session/activity.js";

/** Transport and compiler completion must not masquerade as a rendered document. */
export class PreviewActivityState {
  private connection: "preparing" | "connecting" | "connected" | "reconnecting" = "preparing";
  private compiler?: "compiling" | "success" | "error";
  private pending = false;
  private rendered = false;
  private held = false;
  private failed = false;

  get phase(): ActivityPhase {
    return activityPhase({
      connection: this.connection,
      error: this.failed ? "render-error" : null,
      compiler: this.compiler,
      pending: this.pending ? (this.held ? "selection-held" : "rendering") : null,
      rendered: this.rendered,
    });
  }

  connecting() {
    this.connection = "connecting";
  }

  opened() {
    this.connection = "connected";
    this.compiler = undefined;
    this.pending = this.rendered = this.held = this.failed = false;
  }

  disconnected() {
    this.connection = "reconnecting";
    this.pending = false;
  }

  compile(status: string) {
    if (status !== "compiling" && status !== "success" && status !== "error") return;
    this.compiler = status;
    if (status === "compiling") this.rendered = false;
    if (status === "error") this.pending = false;
  }

  frame() {
    this.pending = true;
    this.held = this.failed = false;
  }

  renderActivity(activity: "rendering" | "selection-held") {
    if (this.pending) this.held = activity === "selection-held";
  }

  didRender() {
    if (!this.pending || this.failed || this.connection !== "connected") return;
    this.pending = this.held = this.failed = false;
    this.rendered = true;
  }

  renderError() {
    this.failed = true;
  }
}

/** Paged engine events and native touch selection adapt the shared notice. */
export class PreviewActivity {
  readonly state = new PreviewActivityState();
  private notice: ActivityNotice;

  constructor() {
    const element = document.getElementById("typst-preview-status")!;
    const root = () => document.getElementById("typst-app");
    this.notice = new ActivityNotice(element, {
      phase: () => this.state.phase,
      hasSelection: () => {
        const app = root();
        return Boolean(app && hasTouchSelection(app));
      },
      releaseSelection: () => {
        const app = root();
        if (app && hasTouchSelection(app)) app.ownerDocument.getSelection()?.removeAllRanges();
      },
    });
  }

  refresh() {
    this.notice.refresh();
  }

  dispose() {
    this.notice.dispose();
  }
}
