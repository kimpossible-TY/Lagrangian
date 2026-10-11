import * as vscode from "vscode";
import { getSensibleTextEditorColumn } from "../util";

export interface PreviewSourceJump {
  filepath: string;
  start: [number, number] | null;
  end: [number, number] | null;
}

export enum ScrollSyncModeEnum {
  never,
  onSelectionChangeByMouse,
  onSelectionChange,
}

export type ScrollSyncMode = "never" | "onSelectionChangeByMouse" | "onSelectionChange";

export function getPreviewConfCompat<T>(setting: string) {
  const conf = vscode.workspace.getConfiguration();
  const current = conf.get<T>(`tinymist.preview.${setting}`);
  const legacy = conf.get<T>(`typst-preview.${setting}`);
  return current === conf.inspect<T>(`tinymist.preview.${setting}`)?.defaultValue &&
    legacy !== undefined
    ? legacy
    : current;
}

/** Tinymist's existing mouse/keyboard policy also excludes programmatic reveals. */
export function shouldSyncPreview(
  kind: vscode.TextEditorSelectionChangeKind | undefined,
  mode: ScrollSyncModeEnum,
): boolean {
  return (
    mode !== ScrollSyncModeEnum.never &&
    (kind === vscode.TextEditorSelectionChangeKind.Mouse ||
      (mode === ScrollSyncModeEnum.onSelectionChange &&
        kind === vscode.TextEditorSelectionChangeKind.Keyboard))
  );
}

/** Shared version of the upstream adjacent/multiple-selection admission policy. */
export class PreviewSelectionTracker {
  private previous?: { uri: vscode.Uri; start: vscode.Position; end: vscode.Position };

  shouldReport(editor: vscode.TextEditor): boolean {
    if (editor.selections.length > 1) return false;
    const { start, end } = editor.selection;
    const previous = this.previous;
    if (
      previous?.uri === editor.document.uri &&
      (start.isEqual(previous.start) ||
        end.isEqual(previous.end) ||
        start.isEqual(previous.end) ||
        end.isEqual(previous.start))
    )
      return false;
    this.previous = { uri: editor.document.uri, start, end };
    return true;
  }
}

/** Extracted from tinymist/preview/scrollSource; all preview transports use it. */
export async function revealPreviewSource(
  jump: PreviewSourceJump,
  options: { document?: vscode.TextDocument; viewColumn?: vscode.ViewColumn } = {},
): Promise<void> {
  if (jump.start === null || jump.end === null) return;
  let affiliatedColumn: vscode.ViewColumn | undefined;
  for (const group of vscode.window.tabGroups.all) {
    if (
      group.tabs.some(
        (tab) =>
          (tab.input instanceof vscode.TabInputText ||
            tab.input instanceof vscode.TabInputCustom ||
            tab.input instanceof vscode.TabInputNotebook) &&
          tab.input.uri.fsPath === jump.filepath,
      )
    ) {
      affiliatedColumn = group.viewColumn;
      break;
    }
  }
  const doc =
    options.document ??
    vscode.workspace.textDocuments.find((doc) => doc.uri.fsPath === jump.filepath) ??
    (await vscode.workspace.openTextDocument(jump.filepath));
  const editor = await vscode.window.showTextDocument(
    doc,
    affiliatedColumn ?? options.viewColumn ?? getSensibleTextEditorColumn(),
  );
  const range = new vscode.Range(
    new vscode.Position(...jump.start),
    new vscode.Position(...jump.end),
  );
  editor.selection = new vscode.Selection(range.start, range.end);
  editor.revealRange(range, vscode.TextEditorRevealType.InCenter);
}
