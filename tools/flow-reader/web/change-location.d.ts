/** Ordered hints wait for rendering; existing viewers retain their reading state. */
export class ChangeLocationQueue<Location = [number, number, number]> {
  constructor(preserveReadingState: boolean);
  lastLocation?: Location;
  queue(location: Location, resume?: boolean): void;
  clear(): void;
  afterRender(
    now: number,
    lastGesture: number,
  ): { location: Location; deferred: boolean } | undefined;
}
