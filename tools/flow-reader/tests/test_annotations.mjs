import assert from "node:assert/strict";
import test from "node:test";
import {
  shortAnnotation,
  sideAnnotations,
  popoverPosition,
  labelPosition,
  TextAnnotations,
} from "../web/rendering/annotations.js";
import { routeConnection } from "../web/rendering/graphics/connector-routing.js";

test("footnote registration groups direct callout references and preserves nested hosts", () => {
  const previousDocument = globalThis.document;
  const makeNode = (tag, classes = []) => ({
    tag,
    classes,
    dataset: {},
    children: [],
    parent: null,
    append(node) {
      node.parent = this;
      this.children.push(node);
    },
    after(node) {
      this.inserted = node;
    },
    closest(selector) {
      for (let node = this; node; node = node.parent) {
        if (
          selector
            .split(",")
            .some((part) =>
              part.startsWith(".") ? node.classes.includes(part.slice(1)) : node.tag === part,
            )
        )
          return node;
      }
      return null;
    },
  });
  try {
    globalThis.document = { createElement: (tag) => makeNode(tag) };
    const callout = makeNode("div", ["flow-callout", "flow-proposition"]);
    const paragraph = makeNode("p");
    callout.append(paragraph);
    const references = [];
    for (const [host, target] of [
      [callout, "one"],
      [callout, "two"],
      [callout, "three"],
      [paragraph, "four"],
      [paragraph, "four"],
    ]) {
      const ref = makeNode("sup");
      ref.querySelector = () => ({ hash: `#${target}`, textContent: target });
      host.append(ref);
      references.push(ref);
    }
    const records = [];
    const adapter = {
      register(nodes, note, options) {
        const record = { nodes, note, ...options };
        records.push(record);
        return record;
      },
      loadFootnote() {},
    };
    TextAnnotations.prototype.prepareFootnotes.call(
      adapter,
      { querySelectorAll: () => references },
      "test",
    );
    assert.equal(records.length, 4);
    assert.deepEqual(
      callout.inserted.children.map((node) => node.dataset.footnoteTarget),
      ["one", "two", "three"],
    );
    assert.deepEqual(
      paragraph.inserted.children.map((node) => node.dataset.footnoteTarget),
      ["four"],
    );
    assert.equal(references[3].dataset.readerNote, references[4].dataset.readerNote);
    assert.equal(new Set(references.slice(0, 3).map((node) => node.dataset.readerNote)).size, 3);
  } finally {
    globalThis.document = previousDocument;
  }
});

test("short labels find free space above preceding mathematical lines", () => {
  const target = { left: 100, right: 300, top: 140 };
  const size = { width: 50, height: 20 };
  const bounds = { left: 16, right: 374, top: 30 };
  const ink = [{ left: 16, right: 374, top: 100, bottom: 130 }];
  const box = labelPosition(target, size, bounds, ink);
  assert.deepEqual(box, { left: 175, right: 225, top: 74, bottom: 94 });
  const occupied = [...ink, { left: 160, right: 240, top: 70, bottom: 95 }];
  const next = labelPosition(target, size, bounds, occupied);
  assert.ok(next.right <= 157 || next.left >= 243 || next.bottom <= 67);
  assert.ok(next.top >= bounds.top);
});

test("short labels search horizontal gaps and reject insufficient physical space", () => {
  const target = { left: 90, right: 290, top: 100 };
  const size = { width: 50, height: 20 };
  const bounds = { left: 16, right: 374, top: 60 };
  const ink = [
    { left: 16, right: 110, top: 65, bottom: 95 },
    { left: 175, right: 374, top: 65, bottom: 95 },
  ];
  const box = labelPosition(target, size, bounds, ink);
  assert.ok(box.left >= 113 && box.right <= 172);
  assert.equal(labelPosition(target, { width: 400, height: 20 }, bounds, []), null);
  assert.equal(
    labelPosition(target, size, bounds, [{ left: 16, right: 374, top: 60, bottom: 100 }]),
    null,
  );
});

test("short names count graphemes and words, while rich and explanatory notes open", () => {
  for (const name of ["kernel", "heat kernel", "경계 조건", "e\u0301".repeat(24)])
    assert.equal(shortAnnotation(name), true, name);
  for (const name of ["", "a b c d", "k".repeat(25), "An explanation of the sign."])
    assert.equal(shortAnnotation(name), false, name);
  assert.equal(shortAnnotation("kernel", true), false);
});

test("side notes need both landscape proportions and real space at the reading font", () => {
  const wide = { width: 1280, height: 800, articleWidth: 1128, fontSize: 18 };
  assert.equal(sideAnnotations(wide), true);
  assert.equal(sideAnnotations({ ...wide, height: 1400 }), false);
  assert.equal(sideAnnotations({ ...wide, width: 900 }), false);
  assert.equal(sideAnnotations({ ...wide, articleWidth: 600 }), false);
  assert.equal(sideAnnotations({ ...wide, fontSize: 30 }), false);
});

test("popovers stay within viewport edges and use the space above or below a term", () => {
  const viewport = { top: 80, bottom: 800, left: 12, right: 378 };
  const size = { width: 300, height: 160 };
  const above = popoverPosition({ top: 400, bottom: 430, left: 20, right: 70 }, size, viewport);
  assert.equal(above.left, 12);
  assert.equal(above.top, 230);
  assert.equal(above.side, "above");
  const below = popoverPosition({ top: 85, bottom: 110, left: 330, right: 370 }, size, viewport);
  assert.equal(below.left, 78);
  assert.equal(below.top, 120);
  assert.equal(below.side, "below");
  const tall = popoverPosition(
    { top: 400, bottom: 430, left: 120, right: 200 },
    { width: 300, height: 1000 },
    viewport,
  );
  assert.ok(tall.top >= viewport.top);
  assert.ok(tall.top + tall.maxHeight <= viewport.bottom);
});

test("one outer rail uses viewport margin, stacks in reference order and reserves only article clearance", () => {
  const previous = [
    globalThis.document,
    globalThis.window,
    globalThis.innerHeight,
    globalThis.getComputedStyle,
    globalThis.NodeFilter,
  ];
  const style = () => {
    const values = new Map();
    return {
      getPropertyValue: (key) => values.get(key) ?? "",
      setProperty: (key, value) => values.set(key, value),
      removeProperty: (key) => values.delete(key),
    };
  };
  const classes = (...names) => {
    const values = new Set(names);
    return {
      contains: (name) => values.has(name),
      add: (name) => values.add(name),
      remove: (name) => values.delete(name),
    };
  };
  try {
    let measurements = 0;
    globalThis.NodeFilter = { SHOW_TEXT: 4 };
    globalThis.document = {
      documentElement: { clientWidth: 1280 },
      createTreeWalker: () => {
        measurements++;
        return { nextNode: () => null };
      },
    };
    globalThis.window = { getSelection: () => ({ isCollapsed: true }) };
    globalThis.innerHeight = 800;
    for (const leftNotes of [false, true]) {
      for (const margin of [0, 100, 300]) {
        const left = leftNotes ? margin : 0;
        const width = 1280 - margin;
        const article = {
          style: style(),
          classList: classes(...(leftNotes ? ["reader-paragraph-chat"] : [])),
          dataset: {},
          querySelectorAll: () => [],
          getBoundingClientRect: () => ({
            left,
            right: left + width,
            width,
            top: 50,
            bottom:
              350 +
              (parseFloat(article.style.getPropertyValue("--flow-side-bottom-clearance")) || 0),
          }),
        };
        globalThis.getComputedStyle = () => {
          const inset =
            parseFloat(article.style.getPropertyValue("--flow-article-side-inset")) || 0;
          return {
            fontSize: "13px",
            paddingLeft: `${36 + (leftNotes ? inset : 0)}px`,
            paddingRight: `${36 + (leftNotes ? 0 : inset)}px`,
          };
        };
        const records = [220, 100, 70].map((height, index) => {
          const host = {
            style: style(),
            classList: classes(index === 1 ? "flow-callout" : "paragraph"),
            querySelector: () => null,
          };
          const source = {
            closest: () => host,
            compareDocumentPosition: (other) => (other.index < index ? 2 : 4),
            index,
          };
          const note = {
            style: style(),
            classList: classes(),
            dataset: {},
            top: 0,
            left: 0,
            getBoundingClientRect: () => ({
              top: note.top,
              bottom: note.top + height,
              height,
              left: note.left,
            }),
          };
          return {
            source,
            host,
            note,
            nodes: [source],
            reference: { textContent: "" },
            kind: "footnote",
            number: `${index + 1}`,
            anchorTop: [100, 160, 180][index],
          };
        });
        const connectedInk = [];
        const annotations = Object.assign(Object.create(TextAnnotations.prototype), {
          article,
          records: new Map(
            [records[2], records[0], records[1]].map((record) => [record.number, record]),
          ),
          sides: new Map(),
          reserved: new Map(),
          preserve: (change) => change(),
          changed() {},
          schedule() {},
          fragments: (record) => [record.source],
          rectangles: (record) => [{ top: record.anchorTop }],
          place: (note, left, top) => Object.assign(note, { left, top }),
          mode: (record, mode) => {
            record.note.dataset.noteMode = mode;
          },
          footnoteLinks: () => [],
          connect(host, group, labels, ink) {
            connectedInk.push(ink);
          },
        });
        measurements = 0;
        annotations.layout();
        assert.equal(measurements, 1);
        assert.equal(connectedInk.length, 3);
        assert.ok(connectedInk.every((ink) => ink === connectedInk[0]));
        assert.deepEqual(
          records.map((record) => record.note.top),
          [100, 336, 452],
        );
        assert.equal(article.style.getPropertyValue("--flow-side-bottom-clearance"), "172px");
        const railWidth = leftNotes ? 150 : 220;
        assert.equal(
          parseFloat(article.style.getPropertyValue("--flow-article-side-inset")),
          Math.max(0, railWidth + 20 - (margin - 12)),
        );
        assert.ok(records.every((record) => record.note.left === records[0].note.left));
        assert.ok(records[0].note.left >= 12);
        assert.ok(records[0].note.left + railWidth <= 1280 - 12);
        if (margin < railWidth + 32)
          assert.equal(
            leftNotes ? records[0].note.left : 1280 - records[0].note.left - railWidth,
            12,
            "The rail uses all available outside whitespace up to the viewport edge margin",
          );
        for (const { host } of records) {
          assert.equal(host.style.getPropertyValue("--flow-side-height"), "");
          assert.equal(host.style.getPropertyValue("--flow-side-width"), "");
        }
        annotations.layout();
        assert.equal(
          article.style.getPropertyValue("--flow-side-bottom-clearance"),
          "172px",
          "Clearance must not accumulate on repeated layout",
        );
        globalThis.innerHeight = 1400;
        annotations.layout();
        assert.equal(article.style.getPropertyValue("--flow-article-side-inset"), "0px");
        assert.equal(article.style.getPropertyValue("--flow-side-bottom-clearance"), "0px");
        assert.ok(records.every((record) => record.note.dataset.noteMode === "popover"));
        globalThis.innerHeight = 800;
      }
    }
  } finally {
    [
      globalThis.document,
      globalThis.window,
      globalThis.innerHeight,
      globalThis.getComputedStyle,
      globalThis.NodeFilter,
    ] = previous;
  }
});

test("dense side connector still paints its path and reference dot", () => {
  const previous = globalThis.getComputedStyle;
  globalThis.getComputedStyle = () => ({ fontSize: "13px" });
  try {
    const lines = { style: {}, innerHTML: "" };
    const host = { getBoundingClientRect: () => ({ left: 0, right: 700, top: 0, bottom: 1000 }) };
    const record = {
      note: { id: "dense", getBoundingClientRect: () => ({ top: 900, bottom: 950 }) },
      body: { getBoundingClientRect: () => ({ left: 700, right: 900, top: 900, bottom: 950 }) },
    };
    const group = { records: [record], left: 700, width: 200, leftNotes: false, lines };
    const annotations = Object.assign(Object.create(TextAnnotations.prototype), {
      sides: new Map([[host, group]]),
      place() {},
      rectangles: () => [{ left: 40, right: 60, top: 100, bottom: 110 }],
    });
    const ink = Array.from({ length: 300 }, (_, i) => ({
      left: 100 + i * 1.5,
      right: 100.5 + i * 1.5,
      top: 90 + i * 0.08,
      bottom: 90.03 + i * 0.08,
    }));
    ink.push({ left: 640, right: 642, top: 80, bottom: 140 });
    const point = { x: 62, y: 104 };
    const end = { x: 700, y: 904 };
    const points = [point, { x: 692, y: 104 }, { x: 692, y: 904 }, end];
    const localInk = ink.map((rect) => ({ ...rect, top: rect.top + 8, bottom: rect.bottom + 8 }));
    assert.equal(
      routeConnection(
        { kind: "line", points, start: { anchor: "north" }, end: { anchor: "west" } },
        localInk.concat([
          { left: 0, right: 900, top: -1000, bottom: 0 },
          { left: 0, right: 900, top: 1016, bottom: 2016 },
        ]),
        900,
        1016,
        13,
      ),
      null,
    );
    annotations.connect(host, group, [], ink);
    assert.match(lines.innerHTML, /class="flow-side-connector"/);
    assert.match(lines.innerHTML, /class="flow-side-dot"/);
    assert.match(lines.innerHTML, /d="M62,104 L692,104 L692,904 L700,904"/);
  } finally {
    globalThis.getComputedStyle = previous;
  }
});
