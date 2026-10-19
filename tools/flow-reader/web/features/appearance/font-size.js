const defaultFontSize = 13;
// One-time migration preserves later explicit font choices and stored positions.
const fontSizeSetting = "fontSizeV2";

export function createFontSize({ preferences, capture, restore, changed }) {
  let fontSize = defaultFontSize;
  const readingAnchor = capture;
  const restoreAnchor = restore;
  function setFont(size) {
    const anchor = readingAnchor();
    fontSize = Math.max(defaultFontSize, Math.min(30, size));
    document.documentElement.style.setProperty("--reader-font-size", `${fontSize}px`);
    document.querySelector("#reader-size").value = fontSize;
    document.querySelector("#reader-smaller").disabled = fontSize === defaultFontSize;
    document.querySelector("#reader-larger").disabled = fontSize === 30;
    preferences.write(fontSizeSetting, fontSize);
    changed();
    restoreAnchor(anchor);
  }

  const smaller = document.querySelector("#reader-smaller");
  const larger = document.querySelector("#reader-larger");
  const decrease = () => setFont(fontSize - 1);
  const increase = () => setFont(fontSize + 1);
  smaller.addEventListener("click", decrease);
  larger.addEventListener("click", increase);
  return {
    get size() {
      return fontSize;
    },
    set: setFont,
    dispose() {
      smaller.removeEventListener("click", decrease);
      larger.removeEventListener("click", increase);
    },
    restore() {
      setFont(Number(preferences.read(fontSizeSetting, defaultFontSize)) || defaultFontSize);
    },
  };
}
