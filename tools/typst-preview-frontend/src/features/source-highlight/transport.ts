import { selectionPayload } from "../selection/payload";
import type { SelectedText } from "../selection/text-selection";

/** Source writes use the existing compile-validated paged highlight protocol. */
export function highlightSelectionMessage(selection: SelectedText) {
  return `src-highlight ${JSON.stringify(selectionPayload(selection))}`;
}

/** Highlight acknowledgments describe source-write outcomes, never review paint. */
export function presentHighlightResult(
  status: string,
  announce: (korean: string, english: string) => void,
) {
  if (status === "highlighted") {
    announce("소스에 하이라이트 저장됨 · 컴파일 중", "Highlight saved in source · compiling");
  } else if (status === "stale") {
    announce("문서가 갱신됐습니다 · 다시 선택해 주세요", "Document changed · select text again");
  } else if (status === "unmapped" || status === "unsupported") {
    announce(
      "소스 범위를 정확히 연결할 수 없습니다 · Codex 저장을 사용하세요",
      "Cannot safely map this source range · use Save for Codex",
    );
  } else {
    announce(
      "하이라이트 저장 실패 · 다시 선택해 주세요",
      "Could not save highlight · select text again",
    );
  }
}
