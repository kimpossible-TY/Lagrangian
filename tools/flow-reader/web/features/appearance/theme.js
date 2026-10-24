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
    const status = document.querySelector("#reader-appearance-status");
    const radios = [...panel.querySelectorAll('input[name="reader-appearance"]')];
    const names = { system: "자동", light: "라이트", dark: "다크" };
    updateAppearance = () => {
      trigger.dataset.appearance = preference;
      trigger.setAttribute("aria-label", `읽기 설정, 화면 모드: ${names[preference]}`);
      panel.style.setProperty(
        "--appearance-index",
        radios.findIndex((radio) => radio.value === preference),
      );
      for (const radio of radios) {
        radio.checked = radio.value === preference;
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
    updateAppearance();
    control.hidden = true;
    panel.hidden = false;
    trigger.hidden = false;
  });
})();
