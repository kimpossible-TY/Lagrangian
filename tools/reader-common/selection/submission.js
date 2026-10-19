/** An acknowledgment may affect only the range and revision that submitted it. */
export class SelectionSubmission {
  constructor(sameSelection) {
    this.sameSelection = sameSelection;
    this.pending = undefined;
  }

  begin(selection, revision) {
    if (this.pending || !selection || !revision) return undefined;
    return (this.pending = { selection, revision, dismissed: false });
  }

  dismiss() {
    if (this.pending) this.pending.dismissed = true;
  }

  canApply(ticket, current, revision, allowCollapsed = true) {
    return (
      this.pending === ticket &&
      !ticket.dismissed &&
      ticket.revision === revision &&
      (current ? this.sameSelection(current, ticket.selection) : allowCollapsed)
    );
  }

  finish(ticket) {
    if (this.pending === ticket) this.pending = undefined;
  }
}
