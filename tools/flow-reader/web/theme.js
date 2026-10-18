// Apply the browser's saved appearance before the stylesheet paints the page.
(() => {
  const key = "flow-reader:theme:v1";
  const choices = new Set(["system", "light", "dark"]);
  const system = matchMedia("(prefers-color-scheme: dark)");
  let preference = "system";
  try {
    const saved = localStorage.getItem(key);
    if (choices.has(saved)) preference = saved;
  } catch {
    // Appearance remains usable when browser storage is unavailable.
  }
  let updateAppearance = () => {};
  function apply() {
    document.documentElement.dataset.theme =
      preference === "system" ? (system.matches ? "dark" : "light") : preference;
    const control = document.querySelector("#reader-theme");
    if (control) control.value = preference;
    updateAppearance();
  }
  apply();
  system.addEventListener("change", apply);
  window.addEventListener("storage", (event) => {
    if (event.key !== key && event.key !== null) return;
    preference = choices.has(event.newValue) ? event.newValue : "system";
    apply();
  });
  document.addEventListener("DOMContentLoaded", () => {
    const control = document.querySelector("#reader-theme");
    if (!control) return;
    control.value = preference;
    control.addEventListener("change", () => {
      preference = choices.has(control.value) ? control.value : "system";
      apply();
      try {
        localStorage.setItem(key, preference);
      } catch {
        // Keep the explicit choice for this visit even without persistence.
      }
    });

    const trigger = document.querySelector("#reader-appearance-open");
    const panel = document.querySelector("#reader-appearance-panel");
    // Preserve a working native control on older browsers and standalone fixtures.
    if (!trigger || !panel || typeof panel.showPopover !== "function") return;
    const label = document.querySelector("#reader-appearance-label");
    const status = document.querySelector("#reader-appearance-status");
    const radios = [...panel.querySelectorAll('input[name="reader-appearance"]')];
    const names = { system: "자동", light: "라이트", dark: "다크" };
    updateAppearance = () => {
      trigger.dataset.appearance = preference;
      label.textContent = names[preference];
      trigger.setAttribute("aria-label", `화면 모드: ${names[preference]}`);
      panel.style.setProperty(
        "--appearance-index",
        radios.findIndex((radio) => radio.value === preference),
      );
      for (const radio of radios) {
        radio.checked = radio.value === preference;
        radio.autofocus = radio.checked;
      }
      status.textContent =
        preference === "system"
          ? `기기 설정에 따라 ${system.matches ? "다크" : "라이트"} 모드로 표시합니다.`
          : `${names[preference]} 모드를 사용합니다.`;
    };
    for (const radio of radios) {
      radio.addEventListener("change", () => {
        if (!radio.checked) return;
        control.value = radio.value;
        control.dispatchEvent(new Event("change", { bubbles: true }));
      });
    }
    const positionPanel = () => {
      const bounds = trigger.getBoundingClientRect();
      const viewport = window.visualViewport;
      const left = viewport?.offsetLeft ?? 0;
      const top = viewport?.offsetTop ?? 0;
      const width = viewport?.width ?? document.documentElement.clientWidth;
      const height = viewport?.height ?? window.innerHeight;
      const panelWidth = Math.min(320, width - 24);
      const panelTop = Math.max(top + 12, bounds.bottom + 8);
      panel.style.width = `${panelWidth}px`;
      panel.style.left = `${Math.max(left + 12, Math.min(bounds.right - panelWidth, left + width - panelWidth - 12))}px`;
      panel.style.top = `${panelTop}px`;
      panel.style.maxHeight = `${Math.max(0, top + height - panelTop - 12)}px`;
    };
    panel.addEventListener("beforetoggle", (event) => {
      trigger.setAttribute("aria-expanded", String(event.newState === "open"));
      if (event.newState === "open") positionPanel();
    });
    const reposition = () => {
      if (panel.matches(":popover-open")) positionPanel();
    };
    window.addEventListener("resize", reposition);
    window.visualViewport?.addEventListener("resize", reposition);
    window.visualViewport?.addEventListener("scroll", reposition);
    // Text zoom and toolbar changes can move the anchor without a window resize.
    if (typeof ResizeObserver === "function") {
      const observer = new ResizeObserver(reposition);
      observer.observe(trigger.closest(".reader-toolbar"));
    }
    updateAppearance();
    control.hidden = true;
    panel.hidden = false;
    trigger.hidden = false;
  });
})();
