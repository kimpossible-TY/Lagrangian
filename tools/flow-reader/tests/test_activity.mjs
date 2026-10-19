import assert from "node:assert/strict";
import test from "node:test";
import { ReaderActivity, ReaderActivityState } from "../web/features/session/activity.js";

const accepted = (revision, extra = {}) => ({
  revision,
  compiling: false,
  exitCode: 0,
  contentGatePassed: true,
  ...extra,
});
function rendered(state, sequence, revision) {
  state.begin(sequence, revision);
  state.mounting(sequence);
  state.rendered(sequence);
}

test("compiler success waits for accepted HTML publication", () => {
  const state = new ReaderActivityState();
  assert.equal(state.phase(), "waiting");
  state.update(accepted(null, { compiling: true }));
  assert.equal(state.phase(), "compiling");
  state.update(accepted("r1"));
  assert.equal(state.phase(), "loading");
  state.begin(1, "r1");
  state.mounting(1);
  assert.equal(state.phase(), "rendering");
  state.rendered(1);
  assert.equal(state.phase(), "ready");
  state.update(accepted("r1", { compiling: true }));
  assert.equal(state.phase(), "compiling");
});

test("paused publication is static and resumes without reporting early success", () => {
  const state = new ReaderActivityState();
  state.update(accepted("r1"));
  rendered(state, 1, "r1");
  assert.equal(state.phase("selection-held"), "ready", "selection alone is not pending work");
  state.update(accepted("r2"));
  assert.equal(state.phase("selection-held"), "selection-held");
  assert.equal(state.phase("interaction-held"), "interaction-held");
  assert.equal(state.phase(), "loading");
  state.begin(2, "r2");
  state.cancel(2);
  assert.equal(
    state.phase("selection-held"),
    "selection-held",
    "late selection also holds a fetch",
  );
  rendered(state, 3, "r2");
  assert.equal(state.phase(), "ready");
});

test("old section success and failure cannot replace newer work", () => {
  const state = new ReaderActivityState();
  state.update(accepted("r2"));
  state.begin(1, "r1");
  state.begin(2, "r2");
  state.rendered(1);
  state.error(1);
  state.cancel(1);
  assert.equal(state.phase(), "loading");
  state.rendered(2);
  assert.equal(state.phase(), "ready");
  state.update(accepted("r3"));
  assert.equal(state.phase(), "loading", "an older published revision cannot satisfy a newer save");
});

test("local navigation after mounting settles that content without accepting a cancelled fetch", () => {
  const state = new ReaderActivityState();
  state.update(accepted("r1"));
  state.begin(1, "r1");
  state.cancel(1);
  assert.equal(state.phase(), "loading");
  state.begin(2, "r1");
  state.mounting(2);
  state.cancel(2);
  assert.equal(state.phase(), "ready");
});

test("cached publication cannot hide connection, compiler or content-gate errors", () => {
  const state = new ReaderActivityState();
  state.update(accepted("r1", { exitCode: 1 }));
  rendered(state, 1, "r1");
  assert.equal(state.phase(), "compile-error");
  state.update(accepted("r1", { contentGatePassed: false }));
  assert.equal(state.phase(), "compile-error");
  state.update(accepted("r1", { contentGatePassed: false, development: true }));
  assert.equal(state.phase(), "ready");
  state.begin(2, "r1");
  state.connected = false;
  state.rendered(2);
  assert.equal(state.phase(), "reconnecting");
  state.update(accepted("r1"));
  assert.equal(state.phase(), "ready");
  state.begin(3, "r1");
  state.error(3);
  state.update(accepted("r1"));
  assert.equal(state.phase(), "load-error", "healthy polling does not dismiss a section failure");
  rendered(state, 4, "r1");
  assert.equal(state.phase(), "ready");
});

test("selection release is explicit and disposal removes listeners and delayed feedback", () => {
  const previous = [globalThis.document, globalThis.window];
  const listeners = new Map();
  const button = {
    hidden: true,
    addEventListener: (name, fn) => listeners.set(`button:${name}`, fn),
    removeEventListener: (name) => listeners.delete(`button:${name}`),
  };
  const label = {};
  const hint = {};
  const element = {
    dataset: {},
    querySelector: (selector) =>
      selector.endsWith("-release") ? button : selector.endsWith("-label") ? label : hint,
  };
  globalThis.window = {};
  globalThis.document = {
    documentElement: { lang: "ko" },
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: (name) => listeners.delete(name),
  };
  let held = "selection-held";
  let selected = true;
  let resumed = 0;
  const activity = new ReaderActivity(element, {
    held: () => held,
    hasSelection: () => selected,
    releaseSelection: () => {
      selected = false;
      held = null;
    },
    resume: () => resumed++,
  });
  try {
    activity.state.update(accepted("r2"));
    activity.refresh();
    assert.equal(element.dataset.busy, "false");
    assert.equal(button.hidden, false);
    assert.equal(selected, true);
    assert.equal(listeners.has("button:pointerdown"), false, "WebKit taps must reach click");
    const click = listeners.get("button:click");
    click({ stopPropagation() {} });
    assert.equal(selected, false);
    assert.equal(resumed, 1);
    assert.equal(element.dataset.phase, "loading");
    assert.equal(button.hidden, true);
    activity.dispose();
    assert.equal(listeners.size, 0);
    assert.equal(element.hidden, true);
    selected = true;
    held = "selection-held";
    click({ stopPropagation() {} });
    assert.equal(selected, true, "disposed callbacks cannot clear another session's selection");
  } finally {
    activity.dispose();
    [globalThis.document, globalThis.window] = previous;
  }
});
