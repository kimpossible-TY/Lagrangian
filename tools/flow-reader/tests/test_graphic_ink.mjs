import assert from "node:assert/strict";
import test from "node:test";
import { GraphicalAnnotations } from "../web/rendering/graphics/annotations.js";
import { routeConnection } from "../web/rendering/graphics/connector-routing.js";

const box = (left, top, right, bottom) => ({
  left,
  top,
  right,
  bottom,
  width: right - left,
  height: bottom - top,
});
function element(name, paint, parentElement = null, classes = []) {
  return {
    localName: name,
    parentElement,
    dataset: {},
    getClientRects: () => [paint],
    closest(selector) {
      for (let node = this; node; node = node.parentElement) {
        if (
          selector
            .split(",")
            .some((part) =>
              part.startsWith(".")
                ? node.classes?.includes(part.slice(1))
                : part === "[data-flow-mark]"
                  ? node.dataset.flowMark != null
                  : part === node.localName,
            )
        )
          return node;
      }
      return null;
    },
    contains(node) {
      while (node) {
        if (node === this) return true;
        node = node.parentElement;
      }
      return false;
    },
    classes,
  };
}
function measuredInk(candidates, textNodes, marks = []) {
  const previous = { document: globalThis.document, NodeFilter: globalThis.NodeFilter };
  globalThis.NodeFilter = { SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2 };
  globalThis.document = {
    createTreeWalker(_body, _show, filter) {
      const nodes = textNodes.filter((node) => filter.acceptNode(node) === 1);
      return { nextNode: () => nodes.shift() ?? null };
    },
    createRange() {
      let selected;
      return {
        selectNodeContents: (node) => {
          selected = node;
        },
        getClientRects: () => [selected.fontBox],
      };
    },
  };
  try {
    const record = { nodes: marks, scene: { body: { querySelectorAll: () => candidates } } };
    return GraphicalAnnotations.prototype.ink.call({}, record);
  } finally {
    globalThis.document = previous.document;
    globalThis.NodeFilter = previous.NodeFilter;
  }
}

test("a font line box cannot block the clear channel above actual mathematical ink", () => {
  const glyphBox = box(40, 130, 60, 140);
  const glyph = element("mjx-c", glyphBox);
  const glyphText = { textContent: "=", parentElement: glyph, fontBox: box(40, 100, 60, 146) };
  const proseBox = box(75, 160, 95, 175);
  const prose = {
    textContent: "where",
    parentElement: element("span", proseBox),
    fontBox: proseBox,
  };
  const ink = measuredInk([glyph], [glyphText, prose]);
  assert.deepEqual(
    ink.map((item) => item.rect),
    [proseBox, glyphBox],
  );
  const connector = {
    kind: "polyline",
    start: { tag: "a", anchor: "north" },
    end: { tag: "b", anchor: "north" },
    points: [
      { x: 10, y: 120 },
      { x: 50, y: 120 },
    ],
  };
  assert.equal(routeConnection(connector, [glyphText.fontBox], 100, 180, 30), null);
  const result = routeConnection(
    connector,
    ink.map((item) => item.rect),
    100,
    180,
    30,
  );
  assert.equal(result.changed, false);
  assert.deepEqual(result.points, connector.points);
});

test("math paint keeps endpoint identity, measures stretched surfaces once and ignores hidden copies", () => {
  const mark = element("span", box(0, 0, 0, 0));
  mark.dataset.flowMark = "target";
  const glyph = element("mjx-c", box(5, 10, 15, 20), mark);
  const stretch = element("mjx-stretchy-v", box(25, 5, 30, 60));
  const piece = element("mjx-c", box(25, -20, 40, 80), stretch);
  const stage = element("div", box(0, 0, 0, 0), null, ["flow-math-stage"]);
  const hidden = element("mjx-c", box(40, 10, 60, 20), stage);
  const assistive = element("mjx-assistive-mml", box(0, 0, 0, 0));
  const duplicate = element("mjx-c", box(60, 10, 80, 20), assistive);
  const ink = measuredInk([glyph, stretch, piece, hidden, duplicate], [], [mark]);
  assert.deepEqual(
    ink.map((item) => item.rect),
    [glyph.getClientRects()[0], stretch.getClientRects()[0]],
  );
  assert.equal(ink[0].tag, "target");
  assert.equal(ink[0].target, true);
  assert.equal(ink[1].target, false);
});
