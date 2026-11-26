export const CROSS_PROJECT_RETURN_KEY: "lagrangian:cross-project-return:v1";
export const CROSS_PROJECT_PENDING_KEY: "lagrangian:cross-project-pending:v1";
export interface CrossProjectReturnEntry {
  path: string;
  documentTitle: string;
  sectionId: string;
  anchor: string | null;
  /** Viewport scroll position relative to the saved section's document top. */
  scrollOffset: number;
}
export interface CrossProjectPendingReturn {
  version: 1;
  transitionId: string;
  entry: CrossProjectReturnEntry;
}
export function isReturnPath(path: unknown): path is string;
export class CrossProjectReturnStack {
  constructor(options?: { storage?: Pick<Storage, "getItem" | "setItem" | "removeItem"> | null; maxDepth?: number });
  readonly canGoBack: boolean;
  reload(): void;
  push(entry: CrossProjectReturnEntry): boolean;
  pop(): CrossProjectReturnEntry | null;
  peek(): CrossProjectReturnEntry | null;
  clear(): boolean;
  savePending(entry: CrossProjectReturnEntry, transitionId: string): boolean;
  peekPending(path: string): CrossProjectPendingReturn | null;
  consumePending(path: string, transitionId: string): CrossProjectReturnEntry | null;
}
