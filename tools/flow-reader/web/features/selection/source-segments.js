import { logicalTextIndex } from "../../rendering/math/identity.js";

export function sourceSegments(index, start, end) {
  const owner = (point) => {
    const node = point?.start[0];
    const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
    // Equation numbers belong to the surrounding block, not the mathematical
    // expression whose complete source must be selected.
    return (
      element?.closest(".flow-math-view,math") ??
      element?.closest(".flow-equation,.flow-inline-equation") ??
      null
    );
  };
  const groups = [];
  for (let i = start; i < end; i++) {
    const math = owner(index.points[i]);
    let group = groups.at(-1);
    if (!group || group.math !== math) groups.push((group = { math, start: i, end: i }));
    group.end = i + 1;
  }
  return groups.map((group) => {
    const text = index.text.slice(group.start, group.end);
    if (!group.math) return { text };
    const whole = logicalTextIndex(group.math).text;
    return { text, math: true, complete: text.trim() === whole.trim() };
  });
}
