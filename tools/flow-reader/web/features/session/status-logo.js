/** HTML presentation only: ActivityNotice retains labels and release policy. */
export class StatusLogo {
  constructor(element) {
    this.element = element;
    this.trigger = element.querySelector("summary");
    this.announcer = element.ownerDocument.querySelector("#reader-logo-announcement");
    this.label = element.querySelector(".reader-logo-label");
    this.hint = element.querySelector(".reader-logo-hint");
    this.badge = element.querySelector(".reader-logo-badge");
    this.release = element.querySelector(".reader-logo-release");
    this.listeners = new AbortController();
    const { signal } = this.listeners;
    // Preserve native document selection until the explicit release action.
    this.trigger.addEventListener("mousedown", (event) => event.preventDefault(), { signal });
    this.release.addEventListener("mousedown", (event) => event.preventDefault(), { signal });
    this.release.addEventListener("click", () => this.notice?.releaseButton.click(), { signal });
    element.querySelector(".reader-logo-close").addEventListener("click", () => this.close(true), {
      signal,
    });
    document.addEventListener(
      "click",
      (event) => {
        if (!element.contains(event.target)) this.close();
      },
      { signal },
    );
    document.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape" && element.open) {
          event.preventDefault();
          this.close(true);
        }
      },
      { signal },
    );
    document.documentElement.dataset.readerLogo = "true";
  }

  close(focus = false) {
    this.element.open = false;
    if (focus) this.trigger.focus({ preventScroll: true });
  }

  update(phase, notice, offline = false) {
    if (this.disposed) return;
    this.notice = notice;
    const korean = notice.korean;
    const queue = this.element.querySelector("#reader-highlight-queue-status");
    const display =
      offline && ["ready", "reconnecting"].includes(phase)
        ? "offline"
        : phase === "ready" && Number(queue?.dataset.pending) > 0
          ? "sync"
          : phase;
    if (
      phase === "ready" &&
      ["compiling", "loading", "rendering", "waiting"].includes(this.phase) &&
      !offline
    ) {
      this.element.dataset.completed = "true";
      clearTimeout(this.completed);
      this.completed = setTimeout(() => delete this.element.dataset.completed, 1600);
    } else if (phase !== "ready" || offline) {
      clearTimeout(this.completed);
      delete this.element.dataset.completed;
    }
    this.phase = phase;
    this.element.dataset.phase = display;
    const label =
      display === "sync"
        ? korean
          ? "하이라이트 동기화 대기"
          : "Highlights waiting to sync"
        : display === "offline"
          ? korean
            ? "오프라인 읽기"
            : "Reading offline"
          : phase === "ready"
            ? korean
              ? "연결됨 · 최신 문서"
              : "Connected · document up to date"
            : notice.label.textContent;
    if (this.label.textContent !== label) this.label.textContent = label;
    this.trigger.setAttribute("aria-label", `${label} · ${korean ? "상태 보기" : "View status"}`);
    this.trigger.title = label;
    if (this.announcer.textContent !== label) this.announcer.textContent = label;
    const hint =
      display === "offline"
        ? korean
          ? "저장된 문서를 읽고 있습니다."
          : "Reading a saved document."
        : notice.hint.textContent;
    this.hint.textContent = hint;
    this.hint.hidden = !hint;
    this.release.textContent = notice.releaseButton.textContent;
    this.release.hidden = notice.releaseButton.hidden;
    this.badge.textContent = display.endsWith("error")
      ? "!"
      : display.endsWith("held")
        ? "Ⅱ"
        : display === "reconnecting"
          ? "↻"
          : display === "offline"
            ? "⌁"
            : display === "sync"
              ? "•"
              : "";
  }

  dispose() {
    this.disposed = true;
    clearTimeout(this.completed);
    this.listeners.abort();
    this.close();
    this.element.hidden = true;
    delete document.documentElement.dataset.readerLogo;
  }
}
