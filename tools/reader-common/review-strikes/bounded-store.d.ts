/** Same persistence policy for renderer-specific review mark records. */
export class BoundedReviewStore<Mark> {
  constructor(
    storage: Pick<Storage, "getItem" | "setItem"> | undefined,
    keyForDocument: (id: string) => string,
    validMark: (value: unknown) => value is Mark,
  );
  marks: Mark[];
  key?: string;
  setDocument(id: string): void;
  reload(): void;
  add(mark: Mark): boolean;
  undo(): void;
  clear(): void;
  reconcile(keep: (mark: Mark) => boolean): void;
}
