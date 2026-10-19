import assert from "node:assert/strict";
import test from "node:test";
import { ActivityNotice, activityPhase, activityPlacement } from "../session/activity.js";

test("both transports share failure, paused-work and publication priority", () => {
  const signals = { connection: "connected", compiler: "success", rendered: true };
  assert.equal(activityPhase(signals), "ready");
  assert.equal(activityPhase({ ...signals, rendered: false }), "waiting");
  assert.equal(activityPhase({ ...signals, compiler: "compiling" }), "compiling");
  for (const pending of ["loading", "rendering", "selection-held", "interaction-held"]) {
    assert.equal(activityPhase({ ...signals, pending }), pending);
    assert.equal(activityPhase({ ...signals, pending, compiler: "error" }), "compile-error");
    assert.equal(activityPhase({ ...signals, pending, error: "load-error" }), "load-error");
    assert.equal(
      activityPhase({ ...signals, pending, error: "render-error", connection: "reconnecting" }),
      "reconnecting",
    );
  }
});

test("shared viewport placement preserves zoom and adapts only the toolbar offset", () => {
  const viewport = { offsetLeft: 100, offsetTop: 200, width: 196.5, scale: 2 };
  const insets = { left: 0, right: 0, top: 44 };
  const paged = activityPlacement(viewport, insets);
  const html = activityPlacement(viewport, insets, 52);
  assert.equal(paged.top, "242px");
  assert.deepEqual(html, { ...paged, top: "248px" });
  assert.equal(paged.maxWidth, "369px");
  assert.equal(paged.transform, "translateX(-50%) scale(0.5)");
});

test("shared notice owns localization, wait feedback, selection release and cleanup", () => {
  const globals = [
    globalThis.window,
    globalThis.document,
    globalThis.getComputedStyle,
    globalThis.setTimeout,
    globalThis.clearTimeout,
  ];
  const listeners = new Map();
  const timers = new Map();
  let serial = 0;
  globalThis.setTimeout = (callback, delay) => {
    timers.set(++serial, { callback, delay });
    return serial;
  };
  globalThis.clearTimeout = (id) => timers.delete(id);
  globalThis.window = {
    visualViewport: {
      offsetLeft: 0,
      offsetTop: 0,
      width: 390,
      scale: 1,
      addEventListener: (name, fn) => listeners.set(`viewport:${name}`, fn),
      removeEventListener: (name) => listeners.delete(`viewport:${name}`),
    },
  };
  globalThis.document = { documentElement: {} };
  globalThis.getComputedStyle = () => ({ getPropertyValue: () => "0px" });
  const button = {
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: (name) => listeners.delete(name),
  };
  const label = {};
  const hint = {};
  const element = {
    dataset: {},
    style: {},
    querySelector: (selector) =>
      selector.endsWith("-release") ? button : selector.endsWith("-label") ? label : hint,
  };
  let phase = "preparing";
  let selected = true;
  let resumed = 0;
  let notice;
  try {
    notice = new ActivityNotice(element, {
      phase: () => phase,
      language: "en",
      hasSelection: () => selected,
      releaseSelection: () => {
        selected = false;
        phase = "rendering";
      },
      resume: () => resumed++,
    });
    assert.equal(label.textContent, "Preparing preview…");
    assert.equal(element.style.left, "195px");
    assert.equal(timers.size, 1);
    const waiting = [...timers.values()][0];
    assert.equal(waiting.delay, 15000);
    waiting.callback();
    assert.match(hint.textContent, /Taking longer/);
    phase = "selection-held";
    notice.refresh();
    assert.equal(timers.size, 0);
    assert.equal(element.dataset.busy, "false");
    assert.equal(button.hidden, false);
    assert.equal(selected, true);
    assert.equal(listeners.has("pointerdown"), false, "WebKit touch clicks must not be cancelled");
    const click = listeners.get("click");
    click({ stopPropagation() {} });
    assert.equal(selected, false);
    assert.equal(resumed, 1);
    assert.equal(element.dataset.phase, "rendering");
    assert.equal(button.hidden, true);
    const delayed = [...timers.values()][0].callback;
    notice.dispose();
    assert.equal(timers.size, 0);
    assert.equal(listeners.size, 0);
    assert.equal(element.hidden, true);
    phase = "selection-held";
    selected = true;
    click({ stopPropagation() {} });
    delayed();
    assert.equal(selected, true, "disposed callbacks cannot affect a replacement reader");
    assert.equal(hint.hidden, true);
  } finally {
    notice?.dispose();
    [
      globalThis.window,
      globalThis.document,
      globalThis.getComputedStyle,
      globalThis.setTimeout,
      globalThis.clearTimeout,
    ] = globals;
  }
});
