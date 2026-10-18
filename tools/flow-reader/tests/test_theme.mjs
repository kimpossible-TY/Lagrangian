import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../web/theme.js", import.meta.url), "utf8");
const key = "flow-reader:theme:v1";

function reader({ saved = null, dark = false, blocked = false } = {}) {
  const documentEvents = new Map(),
    windowEvents = new Map(),
    controlEvents = new Map();
  const root = { dataset: {} };
  const control = { value: "system", addEventListener: (name, fn) => controlEvents.set(name, fn) };
  const system = { matches: dark, addEventListener: (_, fn) => (system.changed = fn) };
  let loaded = false;
  const storage = new Map(saved === null ? [] : [[key, saved]]);
  // Existing document settings must survive changing appearance.
  storage.set("flow-reader:fixture:highlights:v1", "saved quotation");
  runInNewContext(source, {
    document: {
      documentElement: root,
      querySelector: () => (loaded ? control : null),
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
  });
  return {
    root,
    control,
    storage,
    mount() {
      loaded = true;
      documentEvents.get("DOMContentLoaded")();
    },
    choose(value) {
      control.value = value;
      controlEvents.get("change")();
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
