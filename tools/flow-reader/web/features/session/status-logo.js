/** HTML presentation only: ActivityNotice retains labels and release policy. */
export class StatusLogo {
  constructor(element, { offline = null } = {}) {
    this.element = element;
    this.offline = offline;
    this.updateWaiting = false;
    this.trigger = element.querySelector("button");
    this.announcer = element.ownerDocument.querySelector("#reader-logo-announcement");
    this.label = element.ownerDocument.querySelector(".reader-logo-label");
    this.hint = element.ownerDocument.querySelector(".reader-logo-hint");
    this.badge = element.querySelector(".reader-logo-badge");
    this.listeners = new AbortController();
    const { signal } = this.listeners;
    // Preserve native document selection until the explicit release action.
    this.trigger.addEventListener("mousedown", (event) => event.preventDefault(), { signal });
    this.popover = element.querySelector("#reader-logo-popover");
    this.trigger.addEventListener(
      "click",
      (event) => {
        if (this.suppressClick && event.detail !== 0) {
          this.suppressClick = false;
          return;
        }
        this.popover.hidden = !this.popover.hidden;
      },
      { signal },
    );
    this.trigger.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Enter" && event.shiftKey) {
          event.preventDefault();
          this.performAction();
        }
      },
      { signal },
    );
    this.trigger.addEventListener(
      "pointerdown",
      (event) => {
        if (!event.isPrimary || event.button !== 0) return;
        this.cancelPress();
        this.suppressClick = false;
        this.press = { id: event.pointerId, x: event.clientX, y: event.clientY };
        this.pressTimer = setTimeout(() => {
          this.pressTimer = null;
          if (!this.press) return;
          this.suppressClick = true;
          this.press = null;
          this.performAction();
        }, 500);
      },
      { signal },
    );
    const doc = element.ownerDocument;
    doc.addEventListener(
      "pointermove",
      (event) => {
        if (this.press?.id !== event.pointerId) return;
        if (Math.hypot(event.clientX - this.press.x, event.clientY - this.press.y) > 10) {
          this.suppressClick = true;
          this.cancelPress();
        }
      },
      { signal },
    );
    doc.addEventListener(
      "pointerup",
      (event) => {
        if (this.press?.id === event.pointerId) this.cancelPress();
      },
      { signal },
    );
    doc.addEventListener(
      "pointercancel",
      (event) => {
        if (this.press?.id === event.pointerId) this.cancelPress();
      },
      { signal },
    );
    doc.addEventListener(
      "pointerdown",
      (event) => {
        if (!element.contains(event.target)) this.popover.hidden = true;
      },
      { signal },
    );
    doc.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape") this.popover.hidden = true;
      },
      { signal },
    );
    document.documentElement.dataset.readerLogo = "true";
  }

  cancelPress() {
    clearTimeout(this.pressTimer);
    this.pressTimer = null;
    this.press = null;
  }

  async performAction() {
    if (this.reloading) return;
    this.popover.hidden = true;
    if (
      this.phase === "selection-held" ||
      this.notice?.phase === "selection-held" ||
      this.element.dataset.phase === "selection-held"
    ) {
      const releaseButton =
        this.notice?.releaseButton ||
        this.element.ownerDocument.querySelector(".reader-activity-release");
      if (releaseButton && !releaseButton.hidden) releaseButton.focus();
      if (this.notice?.hint) this.notice.hint.hidden = false;
      if (this.hint) this.hint.hidden = false;
      return;
    }
    if (this.hasWaitingUpdate && this.offline?.applyUpdate) {
      this.reloading = true;
      this.element.dataset.phase = "loading";
      this.trigger.setAttribute(
        "aria-label",
        (this.notice?.korean ?? true) ? "업데이트 적용 중" : "Applying update",
      );
      try {
        const applied = await this.offline.applyUpdate();
        if (applied) window.location.reload();
        else {
          this.reloading = false;
          if (this.notice) this.update(this.notice.phase, this.notice, Boolean(this.offlineMode));
          else delete this.element.dataset.phase;
        }
      } catch {
        this.reloading = false;
        if (this.notice) this.update(this.notice.phase, this.notice, Boolean(this.offlineMode));
      }
      return;
    }
    this.reloading = true;
    this.element.dataset.phase = "loading";
    this.trigger.setAttribute(
      "aria-label",
      (this.notice?.korean ?? true) ? "새로고침 중" : "Refreshing",
    );
    this.reloadTimer = setTimeout(() => window.location.reload(), 180);
  }

  get hasWaitingUpdate() {
    return Boolean(this.offline?.registration?.waiting || this.updateWaiting);
  }

  setUpdateWaiting(waiting) {
    this.updateWaiting = Boolean(waiting);
    if (this.notice) {
      this.update(this.notice.phase, this.notice, Boolean(this.offlineMode));
    } else {
      this.renderBadge();
    }
  }

  renderBadge() {
    const hasUpdate = this.hasWaitingUpdate;
    if (hasUpdate) {
      this.element.dataset.updateWaiting = "true";
      this.badge.dataset.badge = "update";
      if (!this.badge.textContent) this.badge.textContent = "↑";
    } else {
      delete this.element.dataset.updateWaiting;
      delete this.badge.dataset.badge;
      if (this.badge.textContent === "↑") this.badge.textContent = "";
    }
  }

  update(phase, notice, offline = false) {
    if (this.disposed) return;
    this.notice = notice;
    this.offlineMode = offline;
    const korean = notice.korean;
    const queue = this.element.ownerDocument.querySelector("#reader-highlight-queue-status");
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
    const hasUpdate = this.hasWaitingUpdate;
    if (hasUpdate) {
      this.element.dataset.updateWaiting = "true";
      this.badge.dataset.badge = "update";
    } else {
      delete this.element.dataset.updateWaiting;
      delete this.badge.dataset.badge;
    }
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
    const actionLabel = hasUpdate
      ? korean
        ? "업데이트 적용"
        : "Apply update"
      : korean
        ? "새로고침"
        : "Refresh";
    this.trigger.setAttribute("aria-label", `${label} · ${actionLabel}`);
    this.popover.textContent = hasUpdate
      ? `${label} · ${korean ? "업데이트 대기 중" : "Update waiting"}`
      : label;
    if (this.announcer.textContent !== label) this.announcer.textContent = label;
    const hint =
      display === "offline"
        ? korean
          ? "저장된 문서를 읽고 있습니다."
          : "Reading a saved document."
        : notice.hint.textContent;
    this.hint.textContent = hint;
    this.hint.hidden = !hint;
    this.badge.textContent = display.endsWith("error")
      ? "!"
      : display.endsWith("held")
        ? "Ⅱ"
        : display === "reconnecting"
          ? "↻"
          : hasUpdate
            ? "↑"
            : display === "offline"
              ? "⌁"
              : display === "sync"
                ? "•"
                : "";
  }

  dispose() {
    this.disposed = true;
    clearTimeout(this.completed);
    this.cancelPress();
    this.listeners.abort();
    clearTimeout(this.reloadTimer);
    this.element.hidden = true;
    delete document.documentElement.dataset.readerLogo;
  }
}
