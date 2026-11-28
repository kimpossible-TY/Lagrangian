export const minFontSize = 13;
export const maxFontSize = 30;
export const defaultFontSize = 13;
export const clampFontSize = (size) => Math.max(minFontSize, Math.min(maxFontSize, size));
// One-time migration preserves later explicit font choices and stored positions.
const fontSizeSetting = "fontSizeV2";

export function createFontSize({ preferences, capture, restore, changed }) {
  let fontSize = defaultFontSize;
  let preview = null;
  const readingAnchor = capture;
  const restoreAnchor = restore;
  function applyFont(size, anchor, persist) {
    const next = clampFontSize(size);
    fontSize = next;
    document.documentElement.style.setProperty("--reader-font-size", `${fontSize}px`);
    document.querySelector("#reader-size").value = fontSize;
    document.querySelector("#reader-smaller").disabled = fontSize === minFontSize;
    document.querySelector("#reader-larger").disabled = fontSize === maxFontSize;
    if (persist) preferences.write(fontSizeSetting, fontSize);
    changed();
    restoreAnchor(anchor);
  }

  function setFont(size) {
    const anchor = preview ? preview.anchor : readingAnchor();
    preview = null;
    applyFont(size, anchor, true);
  }

  function previewFont(size) {
    if (size === fontSize) return;
    preview ??= { size: fontSize, anchor: readingAnchor() };
    applyFont(size, preview.anchor, false);
  }

  function cancelPreview() {
    if (!preview) {
      changed();
      return;
    }
    const previous = preview;
    preview = null;
    applyFont(previous.size, previous.anchor, false);
  }

  const smaller = document.querySelector("#reader-smaller");
  const larger = document.querySelector("#reader-larger");
  const decrease = () => setFont(fontSize - 1);
  const increase = () => setFont(fontSize + 1);
  const keydown = (event) => {
    if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
    let size;
    if (["+", "="].includes(event.key) || event.code === "NumpadAdd") size = fontSize + 1;
    else if (["-", "_"].includes(event.key) || event.code === "NumpadSubtract") size = fontSize - 1;
    else if (event.key === "0" || event.code === "Numpad0") size = defaultFontSize;
    else return;
    event.preventDefault();
    setFont(size);
  };
  const keyboardTarget = window;
  keyboardTarget.addEventListener("keydown", keydown);
  smaller.addEventListener("click", decrease);
  larger.addEventListener("click", increase);
  return {
    get size() {
      return fontSize;
    },
    set: setFont,
    preview: previewFont,
    cancelPreview,
    dispose() {
      if (preview) cancelPreview();
      keyboardTarget.removeEventListener("keydown", keydown);
      smaller.removeEventListener("click", decrease);
      larger.removeEventListener("click", increase);
    },
    restore() {
      setFont(Number(preferences.read(fontSizeSetting, defaultFontSize)) || defaultFontSize);
    },
  };
}
