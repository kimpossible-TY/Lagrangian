import { logicalTextIndex } from "../../rendering/math/identity.js";

function insideSurrogatePair(text, offset) {
  const before = text.charCodeAt(offset - 1);
  const after = text.charCodeAt(offset);
  return before >= 0xd800 && before <= 0xdbff && after >= 0xdc00 && after <= 0xdfff;
}

export function sourceSegments(index, start, end) {
  const owner = (point) => {
    const node = point?.start[0];
    const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
    // Equation numbers belong to the surrounding block, not the mathematical
    // expression whose complete source must be selected.
    if (element?.closest(".flow-equation-number")) return null;
    const math = element?.closest(".flow-math-view,math");
    if (math) return math;
    const equation = element?.closest(".flow-equation,.flow-inline-equation");
    if (!equation || equation.querySelector?.(".flow-math-view,math")) return null;
    return equation;
  };
  const groups = [];
  for (let i = start; i < end; i++) {
    const math = owner(index.points[i]);
    let group = groups.at(-1);
    if (!group || group.math !== math) groups.push((group = { math, start: i, end: i }));
    group.end = i + 1;
  }
  return groups.map((group) => {
    const segStart = insideSurrogatePair(index.text, group.start) ? group.start - 1 : group.start;
    const segEnd = insideSurrogatePair(index.text, group.end) ? group.end + 1 : group.end;
    let before = Math.max(0, segStart - 64);
    let after = Math.min(index.text.length, segEnd + 64);
    if (insideSurrogatePair(index.text, before)) before++;
    if (insideSurrogatePair(index.text, after)) after--;
    const text = index.text.slice(segStart, segEnd);
    const prefix = index.text.slice(before, segStart).trim();
    const suffix = index.text.slice(segEnd, after).trim();
    if (!group.math) return { text };
    const whole = logicalTextIndex(group.math).text;
    return {
      text,
      math: true,
      complete: text.trim() === whole.trim(),
      start: segStart,
      end: segEnd,
      prefix,
      suffix,
    };
  });
}
