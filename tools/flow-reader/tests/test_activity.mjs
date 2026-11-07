import assert from "node:assert/strict";
import test from "node:test";
import { ReaderActivity, ReaderActivityState } from "../web/features/session/activity.js";
import { StatusLogo } from "../web/features/session/status-logo.js";

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
  assert.equal(state.phase(), "content-error");
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

test("HTML rejection is distinct from compilation failure and clears on retry or acceptance", () => {
  const state = new ReaderActivityState();
  const rejected = accepted("r1", { contentGatePassed: false });
  state.update(rejected);
  assert.equal(state.phase(), "content-error", "late viewers receive the rejection reason");
  rendered(state, 1, "r1");
  assert.equal(
    state.phase("selection-held"),
    "content-error",
    "cached content cannot clear rejection",
  );
  state.connected = false;
  assert.equal(state.phase(), "reconnecting");
  state.update({ ...rejected, compiling: true });
  assert.equal(state.phase(), "compiling", "a retry supersedes the old rejection");
  state.update({ ...rejected, exitCode: 1 });
  assert.equal(state.phase(), "compile-error", "nonzero exit remains a compiler failure");
  state.update(rejected);
  state.begin(2, "r1");
  state.error(2);
  assert.equal(state.phase(), "load-error");
  rendered(state, 3, "r1");
  assert.equal(state.phase(), "content-error");
  state.update(accepted("r2"));
  assert.equal(state.phase(), "loading");
  rendered(state, 4, "r2");
  assert.equal(state.phase(), "ready");
});

test("HTML validation notices explain successful compilation in either UI language", () => {
  const previous = [globalThis.document, globalThis.window];
  globalThis.window = {};
  try {
    for (const language of ["ko", "en"]) {
      globalThis.document = {
        documentElement: { lang: language },
        addEventListener() {},
        removeEventListener() {},
      };
      const button = { addEventListener() {}, removeEventListener() {} };
      const label = {};
      const hint = {};
      const element = {
        dataset: {},
        querySelector: (selector) =>
          selector.endsWith("-release") ? button : selector.endsWith("-label") ? label : hint,
      };
      const activity = new ReaderActivity(element, {
        held: () => null,
        hasSelection: () => false,
      });
      try {
        activity.state.update(accepted("r1", { contentGatePassed: false }));
        activity.refresh();
        assert.equal(element.dataset.phase, "content-error");
        assert.equal(element.dataset.busy, "false");
        assert.equal(element.hidden, false);
        assert.equal(hint.hidden, false);
        assert.match(label.textContent, language === "ko" ? /HTML.*갱신 보류/ : /HTML.*withheld/);
        assert.match(
          hint.textContent,
          language === "ko" ? /컴파일은 성공/ : /Compilation succeeded/,
        );
      } finally {
        activity.dispose();
      }
    }
  } finally {
    [globalThis.document, globalThis.window] = previous;
  }
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

test("an equal revision from another document cannot report the old content ready", () => {
  const state = new ReaderActivityState();
  state.update(accepted("r1", { documentID: "first" }));
  rendered(state, 1, "r1");
  state.update(accepted("r1", { documentID: "second" }));
  assert.equal(state.phase("selection-held"), "selection-held");
  rendered(state, 2, "r1");
  assert.equal(state.phase(), "ready");
});

function createLogoHarness() {
  const listeners = new Map();
  const classes = new Set();
  const triggerAttrs = new Map([
    ["aria-label", "문서를 기다리는 중…"],
    ["aria-expanded", "false"],
    ["aria-controls", "reader-logo-popover"],
    ["aria-keyshortcuts", "Shift+Enter"],
    ["type", "button"],
  ]);
  let focusedElement = null;

  const trigger = {
    classList: {
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
      contains: (name) => classes.has(name),
    },
    setAttribute: (k, v) => triggerAttrs.set(k, v),
    getAttribute: (k) => triggerAttrs.get(k) ?? null,
    hasAttribute: (k) => triggerAttrs.has(k),
    focus: () => {
      focusedElement = trigger;
    },
    addEventListener: (event, handler) => {
      const list = listeners.get(`trigger:${event}`) || [];
      list.push(handler);
      listeners.set(`trigger:${event}`, list);
    },
    removeEventListener: (event, handler) => {
      const list = listeners.get(`trigger:${event}`) || [];
      listeners.set(
        `trigger:${event}`,
        list.filter((h) => h !== handler),
      );
    },
    dispatchEvent: (event) => {
      const list = listeners.get(`trigger:${event.type}`) || [];
      for (const h of list) h(event);
      return !event.defaultPrevented;
    },
    click: () => {
      const list = listeners.get("trigger:click") || [];
      for (const h of list) h({ type: "click" });
    },
  };

  const popover = { textContent: "", hidden: true };
  const badge = { textContent: "", dataset: {} };
  const announcer = { textContent: "" };
  const label = { textContent: "" };
  const hint = { textContent: "", hidden: true };
  const releaseButton = {
    textContent: "",
    hidden: true,
    focus: () => {
      focusedElement = releaseButton;
    },
  };

  const element = {
    dataset: {},
    contains: (target) => target === trigger || target === popover,
    ownerDocument: {
      addEventListener: (event, handler) => {
        const list = listeners.get(`document:${event}`) || [];
        list.push(handler);
        listeners.set(`document:${event}`, list);
      },
      querySelector: (selector) => {
        if (selector === "#reader-logo-announcement") return announcer;
        if (selector === ".reader-logo-label") return label;
        if (selector === ".reader-logo-hint") return hint;
        if (selector === ".reader-activity-release") return releaseButton;
        return null;
      },
    },
    querySelector: (selector) => {
      if (selector === "button") return trigger;
      if (selector === ".reader-logo-badge") return badge;
      if (selector === "#reader-logo-popover") return popover;
      return null;
    },
  };

  return {
    element,
    trigger,
    badge,
    popover,
    dispatchDocument: (event) => {
      for (const handler of listeners.get(`document:${event.type}`) || []) handler(event);
    },
    announcer,
    label,
    hint,
    releaseButton,
    listeners,
    getFocused: () => focusedElement,
  };
}

test("status logo clears confirmation after animation, pointerdown, and disposal", () => {
  const previousDocument = globalThis.document;
  const harness = createLogoHarness();
  globalThis.document = { documentElement: { dataset: {} } };
  const logo = new StatusLogo(harness.element);
  const confirmed = "reader-logo-confirmed";
  try {
    harness.trigger.classList.add(confirmed);
    harness.trigger.dispatchEvent({ type: "animationend", target: harness.trigger, animationName: "other" });
    assert.equal(harness.trigger.classList.contains(confirmed), true);
    harness.trigger.dispatchEvent({ type: "animationend", target: harness.trigger, animationName: "logo-confirm" });
    assert.equal(harness.trigger.classList.contains(confirmed), false);

    harness.trigger.classList.add(confirmed);
    harness.trigger.dispatchEvent({ type: "pointerdown", isPrimary: false });
    assert.equal(harness.trigger.classList.contains(confirmed), false);

    harness.trigger.classList.add(confirmed);
    logo.dispose();
    assert.equal(harness.trigger.classList.contains(confirmed), false);
  } finally {
    logo.dispose();
    globalThis.document = previousDocument;
  }
});

test("status logo accessible name reflects state, language, and update readiness", () => {
  const previous = [globalThis.document, globalThis.window];
  const harness = createLogoHarness();
  globalThis.document = {
    documentElement: { dataset: {} },
    addEventListener: () => {},
    removeEventListener: () => {},
  };
  globalThis.window = { location: { reload: () => {} } };
  try {
    const logo = new StatusLogo(harness.element);
    assert.equal(
      harness.trigger.getAttribute("aria-label"),
      "문서를 기다리는 중…",
      "initial accessible name reflects current state only",
    );
    assert.equal(
      harness.trigger.getAttribute("aria-keyshortcuts"),
      "Shift+Enter",
      "exposes keyboard shortcut",
    );
    assert.equal(
      harness.trigger.getAttribute("aria-expanded"),
      "false",
      "popover closed initially",
    );
    assert.equal(
      harness.trigger.getAttribute("aria-controls"),
      "reader-logo-popover",
      "controls the status popover",
    );

    const noticeKo = {
      korean: true,
      phase: "ready",
      label: { textContent: "연결됨 · 최신 문서" },
      hint: { textContent: "" },
    };
    logo.update("ready", noticeKo);
    assert.equal(
      harness.trigger.getAttribute("aria-label"),
      "연결됨 · 최신 문서",
      "Korean accessible name",
    );
    assert.match(
      harness.trigger.getAttribute("aria-description") || "",
      /새로고침/,
      "Korean description mentions refresh",
    );

    const noticeEn = {
      korean: false,
      phase: "ready",
      label: { textContent: "Connected · document up to date" },
      hint: { textContent: "" },
    };
    logo.update("ready", noticeEn);
    assert.equal(
      harness.trigger.getAttribute("aria-label"),
      "Connected · document up to date",
      "English accessible name",
    );
    assert.match(
      harness.trigger.getAttribute("aria-description") || "",
      /Refresh|refresh/,
      "English description mentions refresh",
    );

    logo.setUpdateWaiting(true);
    assert.equal(
      harness.trigger.getAttribute("aria-label"),
      "Connected · document up to date",
      "accessible name reflects current state without action suffix",
    );
    assert.match(
      harness.trigger.getAttribute("aria-description") || "",
      /apply update|update/i,
      "description reflects update action when waiting",
    );
    assert.equal(harness.badge.textContent, "↑", "shows update badge");

    logo.dispose();
  } finally {
    [globalThis.document, globalThis.window] = previous;
  }
});

test("status logo keyboard activation and waiting-SW apply path", async () => {
  const previous = [globalThis.document, globalThis.window];
  let reloadCalled = 0;
  let updateApplied = 0;
  const mockOffline = {
    registration: { waiting: {} },
    applyUpdate: async () => {
      updateApplied++;
      return true;
    },
  };
  const harness = createLogoHarness();
  globalThis.document = {
    documentElement: { dataset: {} },
    addEventListener: () => {},
    removeEventListener: () => {},
  };
  globalThis.window = {
    location: {
      reload: () => {
        reloadCalled++;
      },
    },
  };
  try {
    const logo = new StatusLogo(harness.element, { offline: mockOffline });
    const notice = {
      korean: true,
      phase: "ready",
      label: { textContent: "연결됨 · 최신 문서" },
      hint: { textContent: "" },
    };
    logo.update("ready", notice);
    assert.equal(logo.hasWaitingUpdate, true);
    assert.equal(harness.badge.textContent, "↑", "badge shows update symbol");
    assert.equal(harness.element.dataset.updateWaiting, "true");

    // Keyboard activation (Enter / Space) triggers click
    harness.trigger.dispatchEvent({
      type: "keydown",
      key: "Enter",
      shiftKey: true,
      preventDefault: () => {},
      isTrusted: false,
      target: harness.trigger,
    });
    // Wait microtasks for async applyUpdate
    await new Promise((resolve) => setTimeout(resolve, 15));

    assert.equal(updateApplied, 1, "calls offline.applyUpdate() on logo activation");
    assert.equal(reloadCalled, 1, "reloads after applyUpdate resolves");

    logo.dispose();
  } finally {
    [globalThis.document, globalThis.window] = previous;
  }
});

test("status logo held-state click behavior and mousedown preventDefault", () => {
  const previous = [globalThis.document, globalThis.window];
  let reloadCalled = 0;
  const harness = createLogoHarness();
  globalThis.document = {
    documentElement: { dataset: {} },
    addEventListener: () => {},
    removeEventListener: () => {},
  };
  globalThis.window = {
    location: {
      reload: () => {
        reloadCalled++;
      },
    },
  };
  try {
    const logo = new StatusLogo(harness.element);
    let preventDefaultCalled = false;
    harness.trigger.dispatchEvent({
      type: "mousedown",
      preventDefault: () => {
        preventDefaultCalled = true;
      },
    });
    assert.equal(
      preventDefaultCalled,
      true,
      "mousedown prevents default to keep document selection",
    );
    let contextMenuPrevented = false;
    harness.trigger.dispatchEvent({
      type: "contextmenu",
      preventDefault: () => {
        contextMenuPrevented = true;
      },
    });
    assert.equal(contextMenuPrevented, true, "contextmenu prevents default on logo button");

    const notice = {
      korean: true,
      phase: "selection-held",
      label: { textContent: "텍스트 선택 중 · 갱신 일시정지" },
      hint: { textContent: "선택을 해제해야 새 내용이 표시됩니다.", hidden: true },
      releaseButton: harness.releaseButton,
    };
    harness.releaseButton.hidden = false;
    logo.update("selection-held", notice);

    assert.equal(harness.badge.textContent, "Ⅱ", "shows held badge");

    // The action while selection-held must NOT reload.
    harness.trigger.dispatchEvent({
      type: "keydown",
      key: "Enter",
      shiftKey: true,
      preventDefault() {},
    });
    assert.equal(reloadCalled, 0, "does not reload in held state");
    assert.equal(
      harness.getFocused(),
      harness.releaseButton,
      "focuses release button on logo click during selection-held",
    );
    assert.equal(harness.hint.hidden, false, "shows hint");

    logo.dispose();
  } finally {
    [globalThis.document, globalThis.window] = previous;
  }
});

test("status logo tap, dismissal, and deliberate pointer action", async () => {
  const previous = [globalThis.document, globalThis.window];
  const harness = createLogoHarness();
  let reloads = 0;
  globalThis.document = { documentElement: { dataset: {} } };
  globalThis.window = { location: { reload: () => reloads++ } };
  const logo = new StatusLogo(harness.element);
  try {
    logo.update("ready", {
      korean: false,
      phase: "ready",
      label: { textContent: "Ready" },
      hint: { textContent: "" },
    });
    const down = {
      type: "pointerdown",
      isPrimary: true,
      button: 0,
      pointerId: 1,
      clientX: 10,
      clientY: 10,
    };
    harness.trigger.dispatchEvent(down);
    harness.dispatchDocument({ type: "pointerup", pointerId: 1 });
    harness.trigger.click();
    assert.equal(harness.popover.hidden, false);
    assert.equal(harness.trigger.getAttribute("aria-expanded"), "true");
    assert.match(harness.popover.textContent, /Connected/);
    assert.equal(reloads, 0);
    harness.dispatchDocument({ type: "keydown", key: "Escape" });
    assert.equal(harness.popover.hidden, true);
    assert.equal(harness.trigger.getAttribute("aria-expanded"), "false");
    harness.trigger.click();
    assert.equal(harness.trigger.getAttribute("aria-expanded"), "true");
    harness.trigger.click();
    assert.equal(harness.popover.hidden, true);
    assert.equal(harness.trigger.getAttribute("aria-expanded"), "false");
    harness.trigger.click();
    harness.dispatchDocument({ type: "pointerdown", target: {} });
    assert.equal(harness.popover.hidden, true);
    harness.trigger.dispatchEvent(down);
    harness.dispatchDocument({ type: "pointermove", pointerId: 1, clientX: 30, clientY: 10 });
    await new Promise((resolve) => setTimeout(resolve, 520));
    assert.equal(reloads, 0);
    harness.trigger.dispatchEvent(down);
    await new Promise((resolve) => setTimeout(resolve, 710));
    assert.equal(reloads, 0, "standalone long press is inert");
  } finally {
    logo.dispose();
    [globalThis.document, globalThis.window] = previous;
  }
});
