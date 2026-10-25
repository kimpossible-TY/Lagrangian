// Copy text keeps the reading order of ordinary passages and replaces complete
// formulas with their verified Typst source when one is available.
export function composeCopyText(fragments, source = () => null) {
  return (fragments ?? [])
    .map((fragment) => {
      const segments = fragment.segments?.length ? fragment.segments : [{ text: fragment.exact }];
      return segments
        .map((segment) => {
          if (!segment.math || !segment.complete) return segment.text;
          return source(fragment, segment) ?? segment.text;
        })
        .join("");
    })
    .join("\n");
}

export function hasCompleteMath(fragments) {
  return Boolean(
    fragments?.some((fragment) =>
      (fragment.segments ?? []).some((segment) => segment.math && segment.complete),
    ),
  );
}
