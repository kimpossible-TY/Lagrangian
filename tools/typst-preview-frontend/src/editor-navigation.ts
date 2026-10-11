import { PreviewConnection } from "./preview-connection";

type ConnectionCallbacks = ConstructorParameters<typeof PreviewConnection>[1];
export interface PanelScrollRequest {
  event: "panelScrollTo";
  filepath: string;
  line: number;
  character: number;
}

/** Adapt Tinymist's editorScrollTo/panelScrollTo protocol for shared readers. */
export class EditorNavigation {
  private connection?: Pick<PreviewConnection, "dispose">;
  private socket?: Parameters<ConnectionCallbacks["opened"]>[0];
  readonly enabled: boolean;

  constructor(
    host: Pick<Window, "location">,
    scrollPanel: (request: PanelScrollRequest) => void,
    connect: (url: string, callbacks: ConnectionCallbacks) => Pick<PreviewConnection, "dispose"> = (
      url,
      callbacks,
    ) => new PreviewConnection(url, callbacks),
  ) {
    const params = new URL(host.location.href).searchParams;
    let endpoint: URL | undefined;
    try {
      const url = new URL(params.get("tinymist-editor-control") || "");
      const channel = params.get("tinymist-editor") || "";
      if (
        /^[a-f0-9-]{36}$/.test(channel) &&
        ["http:", "https:"].includes(url.protocol) &&
        url.origin === new URL(host.location.href).origin &&
        !url.username &&
        !url.password &&
        url.pathname.endsWith(`/editor/${channel}`)
      ) {
        url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
        endpoint = url;
      }
    } catch {
      /* Ordinary phone URLs have no editor control connection. */
    }
    this.enabled = !!endpoint;
    if (!endpoint) return;
    this.connection = connect(endpoint.toString(), {
      opened: (socket) => {
        this.socket = socket;
      },
      disconnected: () => {
        this.socket = undefined;
      },
      message: (raw) => {
        try {
          const request = JSON.parse(new TextDecoder().decode(raw)) as PanelScrollRequest;
          if (
            request.event === "panelScrollTo" &&
            typeof request.filepath === "string" &&
            [request.line, request.character].every(
              (value) => Number.isSafeInteger(value) && value >= 0 && value <= 0xffffffff,
            )
          )
            scrollPanel(request);
        } catch {
          /* Ignore unrelated/malformed events; never forward memory-file updates. */
        }
      },
    });
  }

  reveal(value: unknown): boolean {
    const jump = value as {
      event?: unknown;
      filepath?: unknown;
      start?: unknown;
      end?: unknown;
    } | null;
    const position = (value: unknown) =>
      Array.isArray(value) &&
      value.length === 2 &&
      value.every((part) => Number.isSafeInteger(part) && part >= 0);
    if (
      !this.socket ||
      this.socket.readyState !== 1 ||
      jump?.event !== "editorScrollTo" ||
      typeof jump.filepath !== "string" ||
      !position(jump.start) ||
      !position(jump.end)
    )
      return false;
    try {
      this.socket.send(
        JSON.stringify({
          event: "editorScrollTo",
          filepath: jump.filepath,
          start: jump.start,
          end: jump.end,
        }),
      );
      return true;
    } catch {
      return false;
    }
  }

  dispose() {
    this.connection?.dispose();
    this.socket = undefined;
  }
}
