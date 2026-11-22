import assert from "node:assert/strict";
import test from "node:test";
import { composeCopyText, hasCompleteMath } from "../web/features/selection/copy-text.js";
import { mathSelectionUnit } from "../web/features/selection/math-snap.js";
import { sourceSegments } from "../web/features/selection/source-segments.js";
import { logicalTextIndex } from "../web/rendering/math/identity.js";

const unit = { id: "math" };
const normalize = (text) => text.replace(/\s+/g, " ").trim();

function withNodeGlobals(t) {
  const previous = Object.getOwnPropertyDescriptor(globalThis, "Node");
  Object.defineProperty(globalThis, "Node", {
    configurable: true,
    value: { ELEMENT_NODE: 1, TEXT_NODE: 3 },
  });
  t.after(() => {
    if (previous) Object.defineProperty(globalThis, "Node", previous);
    else delete globalThis.Node;
  });
}

function matchesSingle(element, selector) {
  const trimmed = selector.trim();
  if (!trimmed) return false;
  if (trimmed.startsWith(".")) return element.classes.has(trimmed.slice(1));
  if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
    const inner = trimmed.slice(1, -1);
    const eq = inner.indexOf("=");
    if (eq < 0) return Object.hasOwn(element.attributes, inner);
    const name = inner.slice(0, eq);
    const value = inner.slice(eq + 1).replace(/^"|"$/g, "");
    return element.attributes[name] === value;
  }
  const attrStart = trimmed.indexOf("[");
  if (attrStart > 0) {
    return (
      matchesSingle(element, trimmed.slice(0, attrStart)) &&
      matchesSingle(element, trimmed.slice(attrStart))
    );
  }
  return element.tagName.toLowerCase() === trimmed.toLowerCase();
}

function el(tagName, { classes = [], attributes = {}, children = [] } = {}) {
  const node = {
    nodeType: 1,
    tagName: tagName.toLowerCase(),
    classes: new Set(classes),
    attributes: { ...attributes },
    parentElement: null,
    childNodes: [],
    hasAttribute(name) {
      return Object.hasOwn(this.attributes, name);
    },
    matches(selector) {
      return selector.split(",").some((part) => matchesSingle(this, part));
    },
    closest(selector) {
      let current = this;
      while (current) {
        if (current.matches(selector)) return current;
        current = current.parentElement;
      }
      return null;
    },
    querySelector(selector) {
      for (const child of this.childNodes) {
        if (child.nodeType !== 1) continue;
        if (child.matches(selector)) return child;
        const found = child.querySelector(selector);
        if (found) return found;
      }
      return null;
    },
  };
  for (const child of children) {
    const wrapped =
      typeof child === "string"
        ? { nodeType: 3, data: child, parentElement: node }
        : Object.assign(child, { parentElement: node });
    node.childNodes.push(wrapped);
  }
  return node;
}

function point({ excluded = false, math = unit } = {}) {
  return {
    nodeType: 1,
    closest(selector) {
      if (selector.includes("mjx-assistive-mml")) return excluded ? unit : null;
      return math;
    },
  };
}

test("complete formulas copy verified Typst while prose keeps its displayed text", () => {
  const fragments = [
    {
      exact: "Before α2+β after",
      segments: [
        { text: "Before " },
        { text: "α2+β", math: true, complete: true },
        { text: " after" },
      ],
    },
    {
      exact: "Partial γ",
      segments: [{ text: "Partial " }, { text: "γ", math: true, complete: false }],
    },
  ];
  assert.equal(
    composeCopyText(fragments, (_fragment, segment) =>
      segment.text === "α2+β" ? "$alpha^2 + beta$" : null,
    ),
    "Before $alpha^2 + beta$ after\nPartial γ",
  );
  assert.equal(hasCompleteMath(fragments), true);
  assert.equal(hasCompleteMath([fragments[1]]), false);
  assert.equal(composeCopyText(null), "");
});

test("the touch target resolves to its containing mathematical view", () => {
  assert.equal(mathSelectionUnit(point()), unit);
  assert.equal(mathSelectionUnit({ nodeType: 3, parentElement: point() }), unit);
  assert.equal(mathSelectionUnit(point({ excluded: true })), null);
  assert.equal(mathSelectionUnit({ nodeType: 1, closest: () => null }), null);
  assert.equal(mathSelectionUnit(null), null);
});

test("equation numbers inside flow-equation emit as plain text, never partial math", (t) => {
  withNodeGlobals(t);
  for (const separator of ["", " "]) {
    const block = el("div", {
      classes: ["flow-equation"],
      attributes: { "data-reader-key": "eq-1" },
      children: [
        el("div", { classes: ["flow-math-view"], children: ["u_t=Δu"] }),
        ...(separator ? [separator] : []),
        el("div", { classes: ["flow-equation-number"], children: ["(4.1.16)"] }),
      ],
    });
    const index = logicalTextIndex(block);
    const segments = sourceSegments(index, 0, index.text.length);
    assert.equal(normalize(segments.map((s) => s.text).join("")), normalize(index.text));
    assert.equal(segments.length, 2);
    assert.equal(segments[0].text, "u_t=Δu");
    assert.equal(segments[0].math, true);
    assert.equal(segments[0].complete, true);
    assert.deepEqual(segments[1], { text: `${separator}(4.1.16)` });
    assert.equal(segments[1].math, undefined);
    assert.equal(
      segments.some((s) => s.math && !s.complete),
      false,
    );

    const numberStart = index.text.indexOf("(4.1.16)");
    const numberOnly = sourceSegments(index, numberStart, index.text.length);
    assert.deepEqual(numberOnly, [{ text: "(4.1.16)" }]);
    assert.equal(
      normalize(numberOnly.map((s) => s.text).join("")),
      normalize(index.text.slice(numberStart)),
    );
  }

  const nativeEquation = el("div", {
    classes: ["flow-equation"],
    attributes: { "data-reader-key": "eq-native" },
    children: [
      el("math", { children: ["a+b=c"] }),
      el("span", { classes: ["flow-equation-number"], children: ["(4.1.17)"] }),
    ],
  });
  const nativeIndex = logicalTextIndex(nativeEquation);
  const nativeSegments = sourceSegments(nativeIndex, 0, nativeIndex.text.length);
  assert.equal(normalize(nativeSegments.map((s) => s.text).join("")), normalize(nativeIndex.text));
  assert.equal(nativeSegments.length, 2);
  assert.equal(nativeSegments[0].math, true);
  assert.equal(nativeSegments[0].complete, true);
  assert.deepEqual(nativeSegments[1], { text: "(4.1.17)" });
});

test("partial and complete math segments classify accurately across math containers", (t) => {
  withNodeGlobals(t);
  const paragraph = el("p", {
    attributes: { "data-reader-key": "p-1" },
    children: [
      "Solve ",
      el("span", {
        classes: ["flow-inline-equation"],
        children: [el("math", { children: ["α+β"] })],
      }),
      " and ",
      el("span", {
        classes: ["flow-inline-equation"],
        children: ["γ+δ"],
      }),
      " now.",
    ],
  });
  const index = logicalTextIndex(paragraph);
  const full = sourceSegments(index, 0, index.text.length);
  assert.equal(normalize(full.map((s) => s.text).join("")), normalize(index.text));
  assert.equal(full.length, 5);
  assert.deepEqual(full[0], { text: "Solve " });
  assert.equal(full[1].text, "α+β");
  assert.equal(full[1].math, true);
  assert.equal(full[1].complete, true);
  assert.deepEqual(full[2], { text: " and " });
  assert.equal(full[3].text, "γ+δ");
  assert.equal(full[3].math, true);
  assert.equal(full[3].complete, true);
  assert.deepEqual(full[4], { text: " now." });

  const partialStart = index.text.indexOf("α");
  const partialEnd = partialStart + 2;
  const partialInline = sourceSegments(index, partialStart, partialEnd);
  assert.equal(
    normalize(partialInline.map((s) => s.text).join("")),
    normalize(index.text.slice(partialStart, partialEnd)),
  );
  assert.equal(partialInline.length, 1);
  assert.equal(partialInline[0].text, "α+");
  assert.equal(partialInline[0].math, true);
  assert.equal(partialInline[0].complete, false);

  const fallbackPartialStart = index.text.indexOf("γ");
  const fallbackPartial = sourceSegments(index, fallbackPartialStart, fallbackPartialStart + 1);
  assert.equal(fallbackPartial.length, 1);
  assert.equal(fallbackPartial[0].text, "γ");
  assert.equal(fallbackPartial[0].math, true);
  assert.equal(fallbackPartial[0].complete, false);

  const equation = el("div", {
    classes: ["flow-equation"],
    attributes: { "data-reader-key": "eq-2" },
    children: [
      el("div", { classes: ["flow-math-view"], children: ["u_t=Δu"] }),
      el("div", { classes: ["flow-equation-number"], children: ["(4.1.18)"] }),
    ],
  });
  const eqIndex = logicalTextIndex(equation);
  const eqPartial = sourceSegments(eqIndex, 0, 3);
  assert.equal(
    normalize(eqPartial.map((s) => s.text).join("")),
    normalize(eqIndex.text.slice(0, 3)),
  );
  assert.equal(eqPartial.length, 1);
  assert.equal(eqPartial[0].text, "u_t");
  assert.equal(eqPartial[0].math, true);
  assert.equal(eqPartial[0].complete, false);
});
