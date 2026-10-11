/** Opt-in, viewer-local bridge. Ordinary mobile/browser URLs never navigate an editor. */
export class EditorNavigation {
  private channel: string | null;
  private callback?: string;

  constructor(
    private host: Pick<Window, "location" | "parent" | "postMessage">,
    private send: typeof fetch = globalThis.fetch,
  ) {
    const params = new URL(host.location.href).searchParams;
    this.channel = params.get("tinymist-editor");
    try {
      const callback = new URL(params.get("tinymist-editor-callback") || "");
      if (
        ["http:", "https:"].includes(callback.protocol) &&
        !callback.username &&
        !callback.password
      ) {
        this.callback = callback.toString();
      }
    } catch {
      /* Ordinary phone/browser URL. */
    }
    if (
      !this.channel ||
      !/^[a-f0-9-]{36}$/.test(this.channel) ||
      (host.parent === host && !this.callback)
    ) {
      this.channel = null;
    }
  }

  get enabled(): boolean {
    return this.channel !== null;
  }

  async reveal(result: {
    status: string;
    filepath?: string;
    line?: number;
    column?: number;
    text_selected?: boolean;
  }): Promise<boolean> {
    if (
      !this.channel ||
      result.status !== "selected" ||
      result.text_selected ||
      typeof result.filepath !== "string" ||
      !Number.isSafeInteger(result.line) ||
      !Number.isSafeInteger(result.column) ||
      result.line! < 1 ||
      result.column! < 1
    )
      return false;
    // The parent validates this iframe's window, exact origin and per-panel channel.
    // Only the selected coordinates are sent, never the source excerpt or selection text.
    const message = {
      type: "flowSourceLocation",
      channel: this.channel,
      filepath: result.filepath,
      line: result.line,
      column: result.column,
    };
    if (this.host.parent !== this.host) {
      this.host.parent.postMessage(message, "*");
      return true;
    }
    try {
      const response = await this.send(this.callback!, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(message),
        signal: AbortSignal.timeout(5000),
      });
      return response.ok;
    } catch {
      return false;
    }
  }
}
