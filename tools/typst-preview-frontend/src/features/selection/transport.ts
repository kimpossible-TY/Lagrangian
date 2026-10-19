import type { SelectedText } from "./text-selection";
import { highlightSelectionMessage } from "../source-highlight/transport";
import { codexContextMessage } from "../codex-context/transport";

/** The paged protocol adapter owns readiness and encodes renderer-native locations. */
export function createSelectionTransport(adapter: {
  ready: () => boolean;
  revision: () => string | undefined;
  send: (message: string) => void;
  announce: (korean: string, english: string) => void;
}) {
  return (action: "save" | "highlight", selection: SelectedText) => {
    if (!adapter.ready() || !adapter.revision() || selection.revision !== adapter.revision()) {
      adapter.announce(
        "문서 갱신 중 · 다시 선택해 주세요",
        "Document updating · select text again",
      );
      return false;
    }
    adapter.announce(
      action === "save" ? "선택한 텍스트 저장 중…" : "하이라이트 적용 중…",
      action === "save" ? "Saving selected text…" : "Applying highlight…",
    );
    adapter.send(
      action === "save" ? codexContextMessage(selection) : highlightSelectionMessage(selection),
    );
    return true;
  };
}
