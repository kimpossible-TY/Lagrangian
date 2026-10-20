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
