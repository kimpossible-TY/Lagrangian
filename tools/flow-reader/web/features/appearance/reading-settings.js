export function readingSettings(panel, trigger) {
  if (typeof panel.hidePopover === "function") {
    return {
      close() {
        if (panel.matches(":popover-open")) panel.hidePopover();
      },
      trigger,
    };
  }
  // Older browsers keep native theme selection and every reading action.
  panel.removeAttribute("popover");
  panel.dataset.fallback = "true";
  trigger.hidden = false;
  trigger.removeAttribute("popovertarget");
  trigger.setAttribute("aria-label", "읽기 설정");
  const close = () => {
    panel.hidden = true;
    trigger.setAttribute("aria-expanded", "false");
  };
  const position = () => {
    const rect = trigger.getBoundingClientRect();
    const top = rect.bottom + 8;
    panel.style.width = `${Math.min(320, document.documentElement.clientWidth - 24)}px`;
    panel.style.right = "12px";
    panel.style.top = `${top}px`;
    panel.style.maxHeight = `${Math.max(0, window.innerHeight - top - 12)}px`;
  };
  trigger.addEventListener("click", () => {
    if (!panel.hidden) {
      close();
      return;
    }
    position();
    panel.hidden = false;
    trigger.setAttribute("aria-expanded", "true");
    panel.querySelector("button:not(:disabled)")?.focus({ preventScroll: true });
  });
  panel.querySelector(".reader-appearance-close").addEventListener("click", () => {
    close();
    trigger.focus();
  });
  document.addEventListener("click", (event) => {
    if (!panel.contains(event.target) && !trigger.contains(event.target)) close();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !panel.hidden) {
      event.preventDefault();
      close();
      trigger.focus();
    }
  });
  window.addEventListener("resize", () => {
    if (!panel.hidden) position();
  });
  return { close, trigger };
}
