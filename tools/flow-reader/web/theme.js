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
  function apply() {
    document.documentElement.dataset.theme =
      preference === "system" ? (system.matches ? "dark" : "light") : preference;
    const control = document.querySelector("#reader-theme");
    if (control) control.value = preference;
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
  });
})();
