import { logoHomeURL, logoGesture } from "../navigation/logo-home-swipe.js";

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
    this.trigger.addEventListener("contextmenu", (event) => event.preventDefault(), { signal });
    this.popover = element.querySelector("#reader-logo-popover");
    this.popoverStatus = element.querySelector(".reader-logo-status") || this.popover;
    this.homeLink = element.querySelector(".reader-logo-home-link");
    this.refreshButton = element.querySelector(".reader-logo-refresh");
    this.refreshButton?.addEventListener("click", () => this.performAction(), { signal });
    this.homeURL = logoHomeURL(element.ownerDocument.defaultView?.location.pathname || "");
    if (this.homeLink) this.homeLink.hidden = !this.homeURL;
    this.trigger.setAttribute("aria-expanded", "false");
    this.trigger.setAttribute("aria-controls", "reader-logo-popover");
    this.trigger.setAttribute("aria-keyshortcuts", "Shift+Enter");
    if (!this.trigger.getAttribute?.("aria-description")) {
      this.trigger.setAttribute("aria-description", "Shift+Enter 또는 메뉴 버튼으로 새로고침");
    }
    this.trigger.addEventListener(
      "click",
      (event) => {
        if (this.suppressClick && event.detail !== 0) {
          this.suppressClick = false;
          return;
        }
        this.setPopoverOpen(this.popover?.hidden);
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
    const doc = element.ownerDocument;
    this.trigger.addEventListener("animationend", (event) => {
      if (event.target === this.trigger && event.animationName === "logo-confirm") {
        this.trigger.classList.remove("reader-logo-confirmed");
      }
    }, { signal });
    this.trigger.addEventListener("pointerdown", (event) => {
      this.trigger.classList?.remove("reader-logo-confirmed");
      if (!event.isPrimary || event.button !== 0) return;
      if (this.gesture && this.gesture.phase !== "done") return;
      this.suppressClick = false;
      this.gesture = logoGesture(null, { type: "down", pointerId: event.pointerId,
        isPrimary: event.isPrimary, button: event.button, x: event.clientX, y: event.clientY,
        width: this.trigger.getBoundingClientRect?.().width || 0 });
      if (!this.homeURL) return;
      this.trigger.setPointerCapture(event.pointerId);
      this.trigger.classList.add("reader-logo-pressing");
      this.pressTimer = setTimeout(() => {
        this.pressTimer = null;
        this.gesture = logoGesture(this.gesture, { type: "hold" });
        if (this.gesture?.action !== "home") return;
        this.suppressClick = true;
        this.trigger.classList.remove("reader-logo-pressing");
        this.trigger.classList.add("reader-logo-confirmed");
        doc.defaultView.navigator.vibrate?.(10);
        this.navigationTimer = setTimeout(() => doc.defaultView.location.assign(this.homeURL), 100);
      }, 500);
    }, { signal });
    doc.addEventListener("pointermove", (event) => {
      if (this.gesture?.id !== event.pointerId) return;
      this.gesture = logoGesture(this.gesture, { type: "move", pointerId: event.pointerId, x: event.clientX, y: event.clientY });
      if (this.gesture.phase === "swiping") {
        this.suppressClick = true;
        this.cancelPress();
        if (this.homeURL && !this.gesture.cancelled && this.gesture.dx > 0) {
          this.trigger.style.setProperty("--logo-swipe-x", `${Math.min(24, this.gesture.dx)}px`);
          this.trigger.classList.add("reader-logo-dragging");
        } else this.resetSwipeVisual();
      }
    }, { signal });
    doc.addEventListener("pointerup", (event) => {
      if (this.gesture?.id !== event.pointerId) return;
      this.gesture = logoGesture(this.gesture, { type: "up", pointerId: event.pointerId, x: event.clientX, y: event.clientY });
      this.cancelPress();
      this.resetSwipeVisual();
      if (this.homeURL && this.gesture.action === "home") {
        this.suppressClick = true;
        doc.defaultView.location.assign(this.homeURL);
      }
    }, { signal });
    doc.addEventListener("pointercancel", (event) => {
      if (this.gesture?.id !== event.pointerId) return;
      this.gesture = logoGesture(this.gesture, { type: "cancel", pointerId: event.pointerId });
      this.cancelPress();
      this.resetSwipeVisual();
      this.suppressClick = true;
    }, { signal });
    doc.addEventListener("pointerdown", (event) => {
      if (this.gesture && this.gesture.phase !== "done" && event.pointerId !== this.gesture.id) {
        this.gesture = logoGesture(this.gesture, { type: "cancel", pointerId: this.gesture.id });
        this.cancelPress();
        this.resetSwipeVisual();
        this.suppressClick = true;
      }
      if (!element.contains(event.target)) this.setPopoverOpen(false);
    }, { signal });
    doc.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape") this.setPopoverOpen(false);
      },
      { signal },
    );
    this.renderBadge();
    document.documentElement.dataset.readerLogo = "true";
  }

  resetSwipeVisual() {
    this.trigger.classList?.remove("reader-logo-dragging");
    this.trigger.style?.removeProperty("--logo-swipe-x");
  }

  description(text, korean) {
    return this.homeURL ? `${text} · ${korean ? "길게 누르거나 오른쪽으로 밀어 홈으로 이동" : "Long-press or swipe right to go home"}` : text;
  }

  setPopoverOpen(open) {
    const isOpen = Boolean(open);
    if (this.popover) this.popover.hidden = !isOpen;
    this.trigger.setAttribute("aria-expanded", isOpen ? "true" : "false");
  }

  cancelPress() {
    clearTimeout(this.pressTimer);
    this.pressTimer = null;
    this.trigger.classList?.remove("reader-logo-pressing");
  }

  async performAction() {
    if (this.reloading) return;
    this.setPopoverOpen(false);
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
    const korean = this.notice?.korean ?? true;
    if (this.refreshButton) this.refreshButton.textContent = korean ? "새로고침" : "Refresh";
    const description = korean
      ? hasUpdate
        ? "Shift+Enter 또는 메뉴 버튼으로 업데이트 적용"
        : "Shift+Enter 또는 메뉴 버튼으로 새로고침"
      : hasUpdate
        ? "Shift+Enter or popover button to apply update"
        : "Shift+Enter or popover button to refresh";
    this.trigger.setAttribute("aria-description", this.description(description, korean));
  }

  update(phase, notice, offline = false) {
    if (this.disposed) return;
    this.notice = notice;
    this.offlineMode = offline;
    const korean = notice.korean;
    if (this.refreshButton) this.refreshButton.textContent = korean ? "새로고침" : "Refresh";
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
    this.trigger.setAttribute("aria-label", label);
    this.trigger.setAttribute("aria-keyshortcuts", "Shift+Enter");
    const description = korean
      ? hasUpdate
        ? "Shift+Enter 또는 메뉴 버튼으로 업데이트 적용"
        : "Shift+Enter 또는 메뉴 버튼으로 새로고침"
      : hasUpdate
        ? "Shift+Enter or popover button to apply update"
        : "Shift+Enter or popover button to refresh";
    this.trigger.setAttribute("aria-description", this.description(description, korean));
    this.popoverStatus.textContent = hasUpdate
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
    this.resetSwipeVisual();
    this.trigger.classList?.remove("reader-logo-confirmed");
    this.gesture = null;
    clearTimeout(this.navigationTimer);
    clearTimeout(this.reloadTimer);
    this.setPopoverOpen(false);
    this.element.hidden = true;
    delete document.documentElement.dataset.readerLogo;
  }
}
