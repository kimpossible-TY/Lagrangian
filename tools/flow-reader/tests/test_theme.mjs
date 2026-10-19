import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(
  new URL("../web/features/appearance/theme.js", import.meta.url),
  "utf8",
);
const key = "flow-reader:theme:v1";

function reader({
  saved = null,
  dark = false,
  blocked = false,
  enhanced = false,
  popover = true,
} = {}) {
  const documentEvents = new Map(),
    windowEvents = new Map(),
    controlEvents = new Map();
  const root = { dataset: {} };
  const control = {
    value: "system",
    addEventListener: (name, fn) => controlEvents.set(name, fn),
    dispatchEvent: (event) => controlEvents.get(event.type)?.(event),
  };
  const trigger = {
    hidden: true,
    dataset: {},
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value;
    },
  };
  const status = {},
    properties = {};
  const radios = ["system", "light", "dark"].map((value) => ({
    value,
    checked: false,
    addEventListener: (_, fn) => {
      properties[value] = fn;
    },
  }));
  const panel = {
    hidden: true,
    showPopover: popover ? () => {} : undefined,
    querySelectorAll: () => radios,
    style: {
      setProperty: (name, value) => {
        properties[name] = value;
      },
    },
    addEventListener() {},
  };
  const elements = new Map([
    ["#reader-theme", control],
    ...(enhanced
      ? [
          ["#reader-appearance-open", trigger],
          ["#reader-appearance-panel", panel],
          ["#reader-appearance-status", status],
        ]
      : []),
  ]);
  const system = { matches: dark, addEventListener: (_, fn) => (system.changed = fn) };
  let loaded = false;
  const storage = new Map(saved === null ? [] : [[key, saved]]);
  // Existing document settings must survive changing appearance.
  storage.set("flow-reader:fixture:highlights:v1", "saved quotation");
  runInNewContext(source, {
    document: {
      documentElement: root,
      querySelector: (selector) => (loaded ? (elements.get(selector) ?? null) : null),
      addEventListener: (name, fn) => documentEvents.set(name, fn),
    },
    window: { addEventListener: (name, fn) => windowEvents.set(name, fn) },
    localStorage: {
      getItem(name) {
        if (blocked) throw new Error("Storage unavailable");
        return storage.get(name) ?? null;
      },
      setItem(name, value) {
        if (blocked) throw new Error("Storage unavailable");
        storage.set(name, value);
      },
    },
    matchMedia: () => system,
    Event,
  });
  return {
    root,
    control,
    storage,
    trigger,
    panel,
    status,
    radios,
    properties,
    mount() {
      loaded = true;
      documentEvents.get("DOMContentLoaded")();
    },
    choose(value) {
      control.value = value;
      controlEvents.get("change")();
    },
    choosePreview(value) {
      for (const radio of radios) radio.checked = radio.value === value;
      properties[value]();
    },
    device(dark) {
      system.matches = dark;
      system.changed();
    },
    otherTab(key, newValue) {
      windowEvents.get("storage")({ key, newValue });
    },
  };
}

test("automatic appearance applies before the toolbar exists and follows the device", () => {
  const page = reader({ dark: true });
  assert.equal(page.root.dataset.theme, "dark");
  page.mount();
  assert.equal(page.control.value, "system");
  page.device(false);
  assert.equal(page.root.dataset.theme, "light");
  page.device(true);
  assert.equal(page.root.dataset.theme, "dark");
});

test("explicit choices survive reloads and override live device changes", () => {
  const page = reader({ dark: true });
  page.mount();
  page.choose("light");
  page.device(true);
  assert.equal(page.root.dataset.theme, "light");
  const reload = reader({ saved: page.storage.get(key), dark: true });
  assert.equal(reload.root.dataset.theme, "light");
  reload.mount();
  assert.equal(reload.control.value, "light");
  reload.choose("dark");
  reload.device(false);
  assert.equal(reload.root.dataset.theme, "dark");
  reload.choose("system");
  assert.equal(reload.root.dataset.theme, "light");
  assert.equal(reload.storage.get("flow-reader:fixture:highlights:v1"), "saved quotation");
});

test("invalid and unavailable storage leave appearance controls usable", () => {
  for (const options of [
    { saved: "invalid", dark: true },
    { blocked: true, dark: true },
  ]) {
    const page = reader(options);
    assert.equal(page.root.dataset.theme, "dark");
    page.mount();
    page.choose("light");
    assert.equal(page.root.dataset.theme, "light");
    page.device(true);
    assert.equal(page.root.dataset.theme, "light");
    page.choose("system");
    assert.equal(page.root.dataset.theme, "dark");
  }
});

test("other tabs synchronize choices and clearing storage returns to automatic", () => {
  const page = reader({ saved: "light", dark: true });
  page.mount();
  page.otherTab("unrelated", "dark");
  assert.equal(page.root.dataset.theme, "light");
  page.otherTab(key, "dark");
  assert.equal(page.control.value, "dark");
  page.otherTab(key, "light");
  assert.equal(page.root.dataset.theme, "light");
  page.otherTab(null, null);
  assert.equal(page.control.value, "system");
  assert.equal(page.root.dataset.theme, "dark");
  page.device(false);
  assert.equal(page.root.dataset.theme, "light");
});

test("preview choices use the existing preference and keep the native fallback available", () => {
  for (const options of [{}, { enhanced: true, popover: false }]) {
    const fallback = reader(options);
    fallback.mount();
    assert.notEqual(fallback.control.hidden, true);
    assert.equal(fallback.trigger.hidden, true);
    fallback.choose("dark");
    assert.equal(fallback.root.dataset.theme, "dark");
  }
  const page = reader({ enhanced: true, saved: "dark" });
  page.mount();
  assert.equal(page.control.hidden, true);
  assert.equal(page.trigger.hidden, false);
  assert.equal(page.panel.hidden, false);
  assert.equal(page.trigger.attributes["aria-label"], "읽기 설정, 화면 모드: 다크");
  assert.deepEqual(
    page.radios.filter((radio) => radio.checked).map((radio) => radio.value),
    ["dark"],
  );
  page.choosePreview("light");
  assert.equal(page.root.dataset.theme, "light");
  assert.equal(page.control.value, "light");
  assert.equal(page.trigger.attributes["aria-label"], "읽기 설정, 화면 모드: 라이트");
  assert.equal(page.storage.get(key), "light");
  assert.equal(page.properties["--appearance-index"], 1);
});

test("preview state follows automatic device changes and other tabs even without writable storage", () => {
  const page = reader({ enhanced: true, blocked: true, dark: true });
  page.mount();
  assert.match(page.status.textContent, /다크/);
  page.device(false);
  assert.match(page.status.textContent, /라이트/);
  page.choosePreview("dark");
  assert.equal(page.root.dataset.theme, "dark");
  assert.equal(page.trigger.dataset.appearance, "dark");
  page.otherTab(key, "light");
  assert.equal(page.trigger.attributes["aria-label"], "읽기 설정, 화면 모드: 라이트");
  assert.deepEqual(
    page.radios.filter((radio) => radio.checked).map((radio) => radio.value),
    ["light"],
  );
  page.otherTab(null, null);
  assert.equal(page.trigger.dataset.appearance, "system");
  assert.equal(page.root.dataset.theme, "light");
  assert.equal(page.properties["--appearance-index"], 0);
});
