/** Opt-in, viewer-local bridge. Ordinary mobile/browser URLs never navigate an editor. */
export class EditorNavigation {
  private channel: string | null;

  constructor(private host: Pick<Window, "location" | "parent" | "postMessage">) {
    this.channel = new URL(host.location.href).searchParams.get("tinymist-editor");
    if (!this.channel || !/^[a-f0-9-]{36}$/.test(this.channel) || host.parent === host) {
      this.channel = null;
    }
  }

  get enabled(): boolean {
    return this.channel !== null;
  }

  reveal(result: {
    status: string;
    filepath?: string;
    line?: number;
    column?: number;
    text_selected?: boolean;
  }): boolean {
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
    this.host.parent.postMessage(
      {
        type: "flowSourceLocation",
        channel: this.channel,
        filepath: result.filepath,
        line: result.line,
        column: result.column,
      },
      "*",
    );
    return true;
  }
}
