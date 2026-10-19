/** Compiler success and obsolete rendering must not masquerade as a ready document. */
export function activityPhase({ connection, error, compiler, pending, rendered }) {
  if (connection === "reconnecting") return "reconnecting";
  if (error) return error;
  if (connection !== "connected") return connection;
  if (compiler === "error") return "compile-error";
  if (pending) return pending;
  if (compiler === "compiling") return "compiling";
  return rendered ? "ready" : "waiting";
}

const labels = {
  preparing: ["미리보기 준비 중…", "Preparing preview…"],
  connecting: ["서버에 연결 중…", "Connecting to server…"],
  waiting: ["문서를 기다리는 중…", "Waiting for document…"],
  compiling: ["문서 컴파일 중…", "Compiling document…"],
  loading: ["새 내용을 불러오는 중…", "Loading document changes…"],
  rendering: ["화면에 그리는 중…", "Rendering document…"],
  "selection-held": ["텍스트 선택 중 · 갱신 일시정지", "Update paused while text is selected"],
  "interaction-held": ["읽기 동작 중 · 갱신 대기", "Update paused while reading"],
  reconnecting: ["연결 끊김 · 다시 연결 중…", "Disconnected · reconnecting…"],
  "compile-error": ["컴파일 오류 · 소스를 확인해 주세요", "Compilation failed · check source"],
  "render-error": [
    "미리보기를 표시하지 못했습니다 · 새로고침해 주세요",
    "Preview failed · reload to retry",
  ],
  "load-error": [
    "내용을 불러오지 못했습니다 · 연결을 확인해 주세요",
    "Could not load content · check the connection",
  ],
  ready: ["", ""],
};

export function activityPlacement(viewport, insets, topOffset = 40) {
  const scale = viewport.scale || 1;
  const left = Math.max(12, insets.left) / scale;
  const right = Math.max(12, insets.right) / scale;
  return {
    left: `${viewport.offsetLeft + (viewport.width + left - right) / 2}px`,
    top: `${viewport.offsetTop + (Math.max(12, insets.top) + topOffset) / scale}px`,
    maxWidth: `${Math.max(1, (viewport.width - left - right) * scale)}px`,
    transform: `translateX(-50%) scale(${1 / scale})`,
    transformOrigin: "top center",
  };
}

/** Extracted from the paged preview; adapters supply signals and native selection. */
export class ActivityNotice {
  constructor(element, adapter) {
    this.element = element;
    this.adapter = adapter;
    this.label = element.querySelector(".reader-activity-label");
    this.hint = element.querySelector(".reader-activity-hint");
    this.releaseButton = element.querySelector(".reader-activity-release");
    this.korean = (adapter.language ?? navigator.language).startsWith("ko");
    this.preserveSelection = (event) => event.preventDefault();
    this.releaseSelection = (event) => {
      event.stopPropagation();
      if (this.disposed || adapter.phase() !== "selection-held" || !adapter.hasSelection()) return;
      adapter.releaseSelection();
      // Native selectionchange resumes the concrete renderer's publication.
      this.refresh();
      adapter.resume?.();
    };
    this.position = () => {
      const viewport = window.visualViewport;
      if (!viewport) return;
      const style = getComputedStyle(document.documentElement);
      const inset = (edge) =>
        Number.parseFloat(style.getPropertyValue(`--reader-activity-safe-${edge}`)) || 0;
      Object.assign(
        this.element.style,
        activityPlacement(
          viewport,
          { left: inset("left"), right: inset("right"), top: inset("top") },
          adapter.topOffset,
        ),
      );
    };
    this.releaseButton.textContent = this.korean
      ? "선택 해제 후 갱신"
      : "Clear selection and update";
    // Cancelling pointerdown suppresses the subsequent tap click in WebKit.
    this.releaseButton.addEventListener("mousedown", this.preserveSelection);
    this.releaseButton.addEventListener("click", this.releaseSelection);
    window.visualViewport?.addEventListener("resize", this.position);
    window.visualViewport?.addEventListener("scroll", this.position);
    this.refresh();
  }

  refresh() {
    if (this.disposed) return;
    const phase = this.adapter.phase();
    this.releaseButton.hidden = phase !== "selection-held" || !this.adapter.hasSelection();
    if (phase !== this.phase) {
      this.phase = phase;
      clearTimeout(this.delayed);
      this.hint.textContent =
        phase === "selection-held"
          ? this.korean
            ? "선택을 해제해야 새 내용이 표시됩니다."
            : "Clear the selection to display pending changes."
          : phase === "interaction-held"
            ? this.korean
              ? "열린 주석·목차를 닫거나 읽기 동작을 마치면 갱신합니다."
              : "Close the open note or outline, or finish the reading gesture to update."
            : (this.adapter.hint?.(phase) ?? "");
      this.hint.hidden = !this.hint.textContent;
      this.element.hidden = phase === "ready";
      this.element.dataset.phase = phase;
      const busy = ![
        "ready",
        "selection-held",
        "interaction-held",
        "compile-error",
        "render-error",
        "load-error",
      ].includes(phase);
      this.element.dataset.busy = String(busy);
      this.label.textContent = labels[phase][this.korean ? 0 : 1];
      if (busy) {
        this.delayed = setTimeout(() => {
          if (this.disposed) return;
          this.hint.textContent = this.korean
            ? "평소보다 오래 걸리고 있습니다 · 서버 상태를 확인해 주세요"
            : "Taking longer than usual · check the server";
          this.hint.hidden = false;
        }, 15000);
      }
    }
    this.position();
  }

  dispose() {
    this.disposed = true;
    clearTimeout(this.delayed);
    this.releaseButton.removeEventListener("mousedown", this.preserveSelection);
    this.releaseButton.removeEventListener("click", this.releaseSelection);
    this.releaseButton.hidden = true;
    window.visualViewport?.removeEventListener("resize", this.position);
    window.visualViewport?.removeEventListener("scroll", this.position);
    this.element.hidden = true;
  }
}
