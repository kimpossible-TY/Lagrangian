export interface SelectionTicket<Selection> {
  selection: Selection;
  revision: string;
  dismissed: boolean;
}

/** Tracks submissions without interpreting renderer-specific selection positions. */
export class SelectionSubmission<Selection> {
  constructor(sameSelection: (left: Selection, right: Selection) => boolean);
  pending?: SelectionTicket<Selection>;
  begin(
    selection: Selection | undefined,
    revision: string | undefined,
  ): SelectionTicket<Selection> | undefined;
  dismiss(): void;
  canApply(
    ticket: SelectionTicket<Selection>,
    current: Selection | undefined | null,
    revision: string | undefined,
    allowCollapsed?: boolean,
  ): boolean;
  finish(ticket: SelectionTicket<Selection>): void;
}
