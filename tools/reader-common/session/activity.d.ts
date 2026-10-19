export type ActivityPhase =
  | "preparing"
  | "connecting"
  | "waiting"
  | "compiling"
  | "loading"
  | "rendering"
  | "selection-held"
  | "interaction-held"
  | "reconnecting"
  | "compile-error"
  | "render-error"
  | "load-error"
  | "ready";

/** Concrete adapters normalize their native signals; this policy owns precedence. */
export function activityPhase(signals: {
  connection: "preparing" | "connecting" | "connected" | "reconnecting";
  error?: "render-error" | "load-error" | null;
  compiler?: "compiling" | "success" | "error";
  pending?: "loading" | "rendering" | "selection-held" | "interaction-held" | null;
  rendered: boolean;
}): ActivityPhase;

export function activityPlacement(
  viewport: Pick<VisualViewport, "offsetLeft" | "offsetTop" | "width" | "scale">,
  insets: { left: number; right: number; top: number },
  topOffset?: number,
): Pick<CSSStyleDeclaration, "left" | "top" | "maxWidth" | "transform" | "transformOrigin">;

/** Shared notice lifecycle; only the adapter may release its reader's selection. */
export class ActivityNotice {
  constructor(
    element: HTMLElement,
    adapter: {
      phase(): ActivityPhase;
      hasSelection(): boolean;
      releaseSelection(): void;
      resume?(): void;
      hint?(phase: ActivityPhase): string | null;
      language?: string;
      topOffset?: number;
    },
  );
  refresh(): void;
  dispose(): void;
}
