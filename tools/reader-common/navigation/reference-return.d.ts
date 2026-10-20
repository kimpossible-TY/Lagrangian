/** One opaque native origin, shared by semantic HTML and paged navigation. */
export class ReferenceReturn<Origin> {
  constructor(
    button: Pick<HTMLElement, "hidden" | "addEventListener" | "removeEventListener">,
    restore: (origin: Origin) => void,
  );
  remember(origin: Origin | null | undefined): void;
  /** Failed/retryable returns do not call consume; obsolete completions are ignored. */
  consume(origin: Origin): void;
  dispose(): void;
}
