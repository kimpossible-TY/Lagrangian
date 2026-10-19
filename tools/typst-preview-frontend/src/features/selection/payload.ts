import type { SelectedText } from "./text-selection";

export function selectionPayload(selection: SelectedText) {
  return {
    ...selection.start,
    revision: selection.revision,
    selection: { text: selection.text, end: selection.end },
  };
}
