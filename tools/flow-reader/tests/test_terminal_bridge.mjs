import assert from "node:assert/strict";
import test from "node:test";
import {
  TerminalEditorConnection,
  installTerminalBridge,
} from "../web/features/editor-sync/terminal-bridge.js";

test("terminal source writes require the configured editor while ordinary readers remain enabled", () => {
  const ordinary = new TerminalEditorConnection(null);
  assert.equal(ordinary.canHighlight(), true);
  const terminal = new TerminalEditorConnection("editor-one");
  assert.equal(terminal.canHighlight(), false);
  terminal.update("editor-one");
  assert.equal(terminal.canHighlight(), true);
  terminal.update("editor-two");
  assert.equal(terminal.canHighlight(), false);
  terminal.update(undefined);
  assert.equal(terminal.canHighlight(), false);
  const attached = new TerminalEditorConnection("own-editor", "private-attachment");
  assert.equal(attached.canHighlight(), false);
  attached.update(null, 1);
  assert.equal(attached.canHighlight(), true);
  attached.update("other-editor", 0);
  assert.equal(attached.canHighlight(), false);
});

test("the browser bridge is opt-in and returns the existing canonical selection", () => {
  assert.equal(globalThis.flowReaderTerminal, undefined);
  installTerminalBridge({ enabled: false });
  assert.equal(globalThis.flowReaderTerminal, undefined);
  const fragments = [{ key: "body", revision: "one", exact: "Selected" }];
  let captured = 0;
  const dispose = installTerminalBridge({
    enabled: true,
    revision: () => "one",
    manifest: () => ({}),
    actions: () => ({ selection: fragments, capture: () => captured++ }),
  });
  assert.equal(globalThis.flowReaderTerminal.state().ready, true);
  const selected = globalThis.flowReaderTerminal.selection();
  assert.deepEqual(selected, { revision: "one", fragments });
  assert.notEqual(selected.fragments, fragments);
  assert.equal(captured, 1);
  fragments[0].revision = "old";
  assert.equal(globalThis.flowReaderTerminal.selection(), null);
  dispose();
  assert.equal(globalThis.flowReaderTerminal, undefined);
});

test("a follow cannot publish after a revision change or a new selection during section loading", async () => {
  const savedCSS = globalThis.CSS;
  globalThis.CSS = { escape: (text) => text };
  try {
    for (const change of ["revision", "selection", "gesture", "dispose"]) {
      let revision = "one",
        active = false,
        gesture = false,
        scrolled = 0,
        loaded = false,
        finish;
      const target = {
        getBoundingClientRect: () => ({ height: 10 }),
        scrollIntoView: () => scrolled++,
      };
      const dispose = installTerminalBridge({
        enabled: true,
        revision: () => revision,
        manifest: () => ({ blocks: { body: "section" } }),
        article: { querySelector: () => (loaded ? target : null) },
        selectionActive: () => active,
        recentGesture: () => gesture,
        textOf: () => "Text",
        loadSection: () =>
          new Promise((resolve) => {
            finish = () => {
              loaded = true;
              resolve();
            };
          }),
      });
      const pending = globalThis.flowReaderTerminal.follow({
        status: "located",
        revision: "one",
        key: "body",
        section: "section",
        exact: "Text",
      });
      if (change === "revision") revision = "two";
      if (change === "selection") active = true;
      if (change === "gesture") gesture = true;
      if (change === "dispose") dispose();
      finish();
      assert.equal(await pending, false, change);
      assert.equal(scrolled, 0, change);
      dispose();
    }
  } finally {
    if (savedCSS === undefined) delete globalThis.CSS;
    else globalThis.CSS = savedCSS;
  }
});
