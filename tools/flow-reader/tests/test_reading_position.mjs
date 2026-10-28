import assert from "node:assert/strict";
import test from "node:test";
import { createReadingPosition } from "../web/features/navigation/reading-position.js";

test("an explicit return survives late layout and releases on reading input", (t) => {
  const document = Object.assign(new EventTarget(), {
    documentElement: { clientWidth: 390 },
    fonts: new EventTarget(),
  });
  let y = 0;
  let shift = 0;
  const window = Object.assign(new EventTarget(), {
    scrollBy: (_x, delta) => {
      y += delta;
      globalThis.scrollY = y;
    },
  });
  const section = {
    dataset: { readerSection: "section-0" },
    getBoundingClientRect: () => ({ top: shift - y, bottom: shift - y + 1000, height: 1000 }),
  };
  const previousGlobals = new Map();
  for (const [name, value] of Object.entries({
    document,
    window,
    scrollY: 0,
    location: { href: "https://reader/" },
    CSS: { escape: (value) => value },
  })) {
    previousGlobals.set(name, globalThis[name]);
    globalThis[name] = value;
  }
  const position = createReadingPosition(
    {
      querySelectorAll: () => [section],
      querySelector: () => section,
    },
    { readBlocks: () => [], readSection: () => "section-0" },
  );
  t.after(() => {
    position.dispose();
    for (const [name, value] of previousGlobals) globalThis[name] = value;
  });
  const origin = { section: "section-0", fraction: 0.2, url: "https://reader/" };
  assert.equal(position.hold(origin), true);
  for (const delta of [116, -190, 6]) {
    shift += delta;
    position.remember();
    assert.equal(position.capture(), origin);
    position.restore(position.capture());
    assert.equal(section.getBoundingClientRect().top + 200, 90);
  }
  shift += 30;
  document.dispatchEvent(new Event("wheel"));
  assert.notEqual(position.capture(), origin);
  assert.equal(position.capture().fraction, 0.17, "direct reading retains its current geometry");
  assert.equal(position.hold(origin), true);
  position.release();
  assert.notEqual(position.capture(), origin, "another navigation releases the return hold");
});

test("a stable block key cannot restore an anchor after its text changes", (t) => {
  const document = Object.assign(new EventTarget(), {
    documentElement: { clientWidth: 390 },
    fonts: new EventTarget(),
  });
  let y = 0;
  const window = Object.assign(new EventTarget(), {
    scrollBy: (_x, delta) => {
      y += delta;
      globalThis.scrollY = y;
    },
  });
  const block = (key, text) => ({
    nodeType: 1,
    childNodes: [{ nodeType: 3, data: text }],
    dataset: { readerKey: key },
    matches: () => false,
    hasAttribute: () => false,
    closest: () => null,
    getBoundingClientRect: () => ({ top: 150 }),
  });
  let blocks = [block("stable:1", "Changed paragraph")];
  const previousGlobals = new Map();
  for (const [name, value] of Object.entries({
    document,
    window,
    Node: { TEXT_NODE: 3, ELEMENT_NODE: 1 },
    scrollY: 0,
  })) {
    previousGlobals.set(name, globalThis[name]);
    globalThis[name] = value;
  }
  const position = createReadingPosition(
    { querySelectorAll: () => [] },
    { readBlocks: () => blocks, readSection: () => "section-0" },
  );
  t.after(() => {
    position.dispose();
    for (const [name, value] of previousGlobals) globalThis[name] = value;
  });

  const anchor = { key: "stable:1", text: "Original paragraph", offset: 0 };
  assert.equal(position.restore(anchor), false);
  assert.equal(y, 0, "changed text cannot inherit the old reading position");

  blocks = [blocks[0], block("new-key:1", "Original paragraph")];
  assert.equal(position.restore(anchor), true, "a unique text match remains a valid fallback");
  assert.equal(y, 60);
});

test("reference anchors retain their viewport-relative vertical position", (t) => {
  const document = Object.assign(new EventTarget(), {
    documentElement: { clientWidth: 390 },
    fonts: new EventTarget(),
  });
  let y = 0;
  let blockTop = 160;
  const window = Object.assign(new EventTarget(), {
    scrollBy: (_x, delta) => {
      y += delta;
      globalThis.scrollY = y;
    },
  });
  const block = {
    nodeType: 1,
    childNodes: [{ nodeType: 3, data: "Referenced passage" }],
    dataset: { readerKey: "passage:1" },
    matches: () => false,
    hasAttribute: () => false,
    closest: () => null,
    getBoundingClientRect: () => ({
      top: blockTop - y,
      bottom: blockTop - y + 400,
      height: 400,
    }),
  };
  const previousGlobals = new Map();
  for (const [name, value] of Object.entries({
    document,
    window,
    Node: { TEXT_NODE: 3, ELEMENT_NODE: 1 },
    scrollY: 0,
    location: { href: "https://reader/" },
  })) {
    previousGlobals.set(name, globalThis[name]);
    globalThis[name] = value;
  }
  const position = createReadingPosition(
    { querySelectorAll: () => [] },
    { readBlocks: () => [block], readSection: () => "section-0" },
  );
  t.after(() => {
    position.dispose();
    for (const [name, value] of previousGlobals) globalThis[name] = value;
  });

  const origin = position.capture(240);
  assert.equal(origin.viewportY, 240);
  assert.equal(origin.offset, -80);
  blockTop = 230;
  assert.equal(position.restore(origin), true);
  assert.equal(block.getBoundingClientRect().top, 160);
  assert.equal(block.getBoundingClientRect().top, origin.viewportY + origin.offset);
});
