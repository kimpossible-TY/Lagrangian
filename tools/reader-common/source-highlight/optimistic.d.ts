export class OptimisticHighlights<Selection> {
  constructor(paint: (selections: Selection[]) => void);
  begin(ticket: { selection: Selection }, snapshot: string): void;
  settle(ticket: { selection: Selection }, status: string): void;
  onDocument(snapshot: string): void;
  repaint(): void;
  dispose(): void;
}
