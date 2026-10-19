/** Renderer adapters retain their document, geometry, retry and publication guards. */
export interface RenderSchedulerOptions {
  render: () => void | Promise<void>;
  blocked?: () => boolean;
  onBlocked?: () => void;
  onIdle?: () => void;
  onError?: (error: unknown) => void;
}

/** Runs at most one asynchronous render, coalescing requests into browser frames. */
export class RenderScheduler {
  constructor(options: RenderSchedulerOptions);
  readonly active: boolean;
  request(delay?: number): void;
  /** Invalidates queued work/completion; an in-flight render must finish before the next starts. */
  cancel(): void;
  dispose(): void;
}
