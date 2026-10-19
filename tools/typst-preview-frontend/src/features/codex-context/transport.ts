import { selectionPayload } from "../selection/payload";
import type { SelectedText } from "../selection/text-selection";

/** Explicit context capture retains page endpoints and the rendered revision. */
export function codexContextMessage(selection: SelectedText) {
  return `src-point ${JSON.stringify(selectionPayload(selection))}`;
}

interface CodexContextResult {
  status: string;
  filepath?: string;
  text_selected?: boolean;
  page?: number;
  line?: number;
}

/** Text and location capture retain the existing focus response and feedback contract. */
export function presentCodexContextResult(
  result: CodexContextResult,
  announce: (korean: string, english: string) => void,
) {
  if (result.status === "selected") {
    const name = result.filepath!.split(/[\\/]/).pop();
    announce(
      `Codex용 ${result.text_selected ? "텍스트" : "위치"} 저장됨 · ${result.page}쪽 · ${name}:${result.line}`,
      `Saved ${result.text_selected ? "text " : ""}for Codex · p. ${result.page} · ${name}:${result.line}`,
    );
  } else if (result.status === "unmapped") {
    announce(
      result.text_selected
        ? `Codex용 텍스트 저장됨 · ${result.page}쪽 · 소스 연결 없음`
        : `${result.page}쪽 위치만 저장됨 · 글자를 탭하면 소스도 연결됩니다`,
      result.text_selected
        ? `Text saved for Codex · p. ${result.page} · source unavailable`
        : `Page ${result.page} location saved · tap text to link its source`,
    );
  } else if (result.status === "stale" || result.status === "not_ready") {
    announce("문서가 갱신됐습니다 · 다시 탭해 주세요", "Document changed · tap again");
  } else {
    announce("위치 저장 실패 · 다시 탭해 주세요", "Could not save location · tap again");
  }
}
