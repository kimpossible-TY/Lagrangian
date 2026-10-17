import assert from "node:assert/strict";
import test from "node:test";
import { matchToken, selectedIntervals } from "../web/math-identity.js";

function token(text, node = {}) {
  let offset = 0;
  return [...text].map((character) => {
    const start = [node, offset];
    offset += character.length;
    return { character, start, end: [node, offset] };
  });
}

test("split tokens map every source character and repeated operators share logical identity", () => {
  const left = token("ab"),
    right = token("cd");
  const points = matchToken("abcd", [left, right]);
  assert.equal(points.length, 4);
  assert.deepEqual(points[2].start, right[0].start);
  const repeated = matchToken("+", [token("+"), token("+")]);
  assert.equal(repeated.length, 1);
  assert.equal(repeated[0].alternatives.length, 2);
  assert.equal(matchToken("abcd", [token("abXd")]), null);
  assert.equal(matchToken("abcd", [token("abc")]), null);
});

test("Unicode symbols retain UTF-16 offsets and source variation selectors", () => {
  const points = matchToken("𝑋ℱ︀", [token("𝑋ℱ\u2061")]);
  assert.equal(points.length, "𝑋ℱ︀".length);
  assert.deepEqual(points[0].start, points[1].start);
  assert.deepEqual(points[0].end, points[1].end);
  assert.deepEqual(points[2].start, points[3].start);
  assert.equal(matchToken("𝑋", [token("X")]).length, 2);
  assert.equal(matchToken("h", [token("ℎ")]).length, 1);
  assert.equal(matchToken("h", [token("ℏ")]), null);
});

test("visual script order cannot add an unselected logical character to a quotation", () => {
  const index = { text: "Γijk", points: [0, 2, 3, 1].map((i) => ({ start: [i, 0], end: [i, 1] })) };
  const range = { comparePoint: (node) => (node <= 1 ? 0 : 1) };
  assert.deepEqual(selectedIntervals(index, range), [
    [0, 1],
    [3, 4],
  ]);
  const all = { comparePoint: () => 0 };
  assert.deepEqual(selectedIntervals(index, all), [[0, 4]]);
});
