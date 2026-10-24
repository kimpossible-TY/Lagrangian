/** Presentation and dismissal for native and fallback reading-settings panels. */
export function readingSettings(panel, trigger) {
  const nativePopover = typeof panel.hidePopover === "function";
  const open = () => (nativePopover ? panel.matches(":popover-open") : !panel.hidden);
  const close = () => {
    if (nativePopover) {
      if (open()) panel.hidePopover();
    } else {
      panel.hidden = true;
      trigger.setAttribute("aria-expanded", "false");
    }
  };
  const dismiss = () => {
    close();
    trigger.focus({ preventScroll: true });
  };
  const position = () => {
    const bounds = trigger.getBoundingClientRect();
    const viewport = window.visualViewport;
    const left = viewport?.offsetLeft ?? 0;
    const top = viewport?.offsetTop ?? 0;
    const width = viewport?.width ?? document.documentElement.clientWidth;
    const height = viewport?.height ?? window.innerHeight;
    // CSS owns the preferred width, including rem sizing under text zoom.
    panel.style.width = `min(var(--reader-settings-width, 21.5rem), ${Math.max(0, width - 24)}px)`;
    const panelWidth = parseFloat(getComputedStyle(panel).width);
    const panelTop = Math.max(top + 12, bounds.bottom + 8);
    panel.style.left = `${Math.max(left + 12, Math.min(bounds.right - panelWidth, left + width - panelWidth - 12))}px`;
    panel.style.top = `${panelTop}px`;
    panel.style.maxHeight = `${Math.max(0, top + height - panelTop - 12)}px`;
  };
  if (nativePopover) {
    panel.addEventListener("beforetoggle", (event) => {
      trigger.setAttribute("aria-expanded", String(event.newState === "open"));
      if (event.newState === "open") position();
    });
  } else {
    // Older browsers keep native theme selection and every reading action.
    panel.removeAttribute("popover");
    panel.dataset.fallback = "true";
    trigger.hidden = false;
    trigger.removeAttribute("popovertarget");
    trigger.setAttribute("aria-label", "읽기 설정");
    trigger.addEventListener("click", () => {
      if (open()) {
        close();
        return;
      }
      position();
      panel.hidden = false;
      trigger.setAttribute("aria-expanded", "true");
      panel.querySelector("button:not(:disabled)")?.focus({ preventScroll: true });
    });
    document.addEventListener("click", (event) => {
      if (!panel.contains(event.target) && !trigger.contains(event.target)) close();
    });
  }
  panel.querySelector(".reader-appearance-close").addEventListener("click", dismiss);
  // WebKit does not consistently restore the invoking button after Escape.
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && open()) {
      event.preventDefault();
      dismiss();
    }
  });
  const reposition = () => {
    if (open()) position();
  };
  window.addEventListener("resize", reposition);
  window.visualViewport?.addEventListener("resize", reposition);
  window.visualViewport?.addEventListener("scroll", reposition);
  const toolbar = trigger.closest(".reader-toolbar");
  if (toolbar && typeof ResizeObserver === "function") {
    new ResizeObserver(reposition).observe(toolbar);
  }
  return { close, trigger };
}
