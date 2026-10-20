/** Preserves renderer-native selections across toolbar pointer and click events. */
export class SelectionPress<Selection> {
  constructor(released?: () => void);
  readonly active: boolean;
  begin(selection: Selection | undefined | null): void;
  release(): void;
  consume(current: Selection | undefined | null): Selection | undefined | null;
  dispose(): void;
}
