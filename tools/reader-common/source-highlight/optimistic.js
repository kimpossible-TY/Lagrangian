/** Temporary paint belongs to its submitted snapshot, never to a later document. */
export class OptimisticHighlights {
  constructor(paint) {
    this.paint = paint;
    this.tickets = new Set();
  }

  begin(ticket, snapshot) {
    if (this.disposed) return;
    this.onDocument(snapshot);
    this.tickets.add(ticket);
    this.repaint();
  }

  settle(ticket, status) {
    if (status !== "highlighted" && this.tickets.delete(ticket)) this.repaint();
  }

  onDocument(snapshot) {
    if (this.snapshot !== snapshot) {
      this.snapshot = snapshot;
      this.tickets.clear();
      this.repaint();
    }
  }

  repaint() {
    if (!this.disposed) this.paint([...this.tickets].map((ticket) => ticket.selection));
  }

  dispose() {
    this.tickets.clear();
    this.repaint();
    this.disposed = true;
  }
}
