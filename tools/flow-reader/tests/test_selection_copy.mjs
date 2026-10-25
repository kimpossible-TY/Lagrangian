import assert from "node:assert/strict";
import test from "node:test";
import { composeCopyText, hasCompleteMath } from "../web/features/selection/copy-text.js";
import { mathSelectionUnit } from "../web/features/selection/math-snap.js";

const unit = { id: "math" };

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
      segments: [
        { text: "Partial " },
        { text: "γ", math: true, complete: false },
      ],
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
