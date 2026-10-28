import { readFile, realpath } from "node:fs/promises";
import { homedir } from "node:os";
import * as path from "node:path";
import * as vscode from "vscode";
import { createBrowserEditorBridge, type BrowserEditorBridge } from "./shared-flow-browser";
import {
  getPreviewConfCompat,
  PreviewSelectionTracker,
  revealPreviewSource,
  ScrollSyncModeEnum,
  shouldSyncPreview,
  type PreviewSourceJump,
  type ScrollSyncMode,
} from "./preview-sync";
import { l10nMsg } from "../l10n";

export interface FlowPreviewProfile {
  id: string;
  name: string;
  root: string;
  entry: string;
  port: number;
  publicURL: string;
}

export function containsPath(root: string, file: string): boolean {
  const relative = path.relative(root, file);
  return (
    relative === "" ||
    (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative))
  );
}

/** Validate the host's managed profiles before resolving a document. */
export function parseFlowProfiles(value: unknown): FlowPreviewProfile[] {
  const settings = value as { schemaVersion?: unknown; profiles?: unknown } | null;
  if (settings?.schemaVersion !== 1 || !Array.isArray(settings.profiles)) {
    throw new Error(l10nMsg("Unsupported Flow profile configuration."));
  }
  return settings.profiles.map((raw: unknown) => {
    const p = raw as FlowPreviewProfile | null;
    if (
      !p ||
      typeof p.id !== "string" ||
      !/^[a-z0-9][a-z0-9-]{0,63}$/.test(p.id) ||
      typeof p.name !== "string" ||
      typeof p.root !== "string" ||
      !path.isAbsolute(p.root) ||
      typeof p.entry !== "string" ||
      !p.entry.endsWith(".typ") ||
      !Number.isInteger(p.port) ||
      p.port < 1024 ||
      p.port > 65535 ||
      typeof p.publicURL !== "string"
    ) {
      throw new Error(l10nMsg("Invalid Flow preview profile."));
    }
    const root = path.resolve(p.root);
    const entry = path.resolve(root, p.entry);
    if (!containsPath(root, entry)) {
      throw new Error(l10nMsg("The Flow entrypoint must be inside its project root."));
    }
    if (p.publicURL) {
      const url = new URL(p.publicURL);
      if (
        url.protocol !== "https:" ||
        url.username ||
        url.password ||
        url.search ||
        url.hash ||
        url.pathname !== "/"
      ) {
        throw new Error(l10nMsg("The Flow public URL must be an HTTPS origin."));
      }
    }
    return { ...p, root, entry };
  });
}

export function selectFlowProfile(
  profiles: FlowPreviewProfile[],
  documentPath: string,
): FlowPreviewProfile {
  const matching = profiles
    .filter((p) => containsPath(p.root, documentPath))
    .sort((a, b) => b.root.length - a.root.length);
  if (!matching.length) {
    throw new Error(
      l10nMsg(
        "No Flow profile contains this document. Configure and start its project in Lagrangian.",
      ),
    );
  }
  if (matching[1]?.root === matching[0].root) {
    throw new Error(
      l10nMsg(
        "Multiple Flow profiles use this project root. Use a unique project root for shared preview.",
      ),
    );
  }
  return matching[0];
}

async function resolveProfile(documentPath: string): Promise<FlowPreviewProfile> {
  const support =
    process.env.FLOW_DATA_DIR || path.join(homedir(), "Library/Application Support/Lagrangian");
  const settings = JSON.parse(await readFile(path.join(support, "profiles.json"), "utf8"));
  const profiles = parseFlowProfiles(settings);
  const canonicalDocument = await realpath(documentPath);
  // Missing unrelated projects must not prevent opening an existing project.
  const canonical = await Promise.all(
    profiles.map(async (p) => {
      try {
        return { ...p, root: await realpath(p.root) };
      } catch {
        return undefined;
      }
    }),
  );
  const profile = selectFlowProfile(
    canonical.filter((p): p is FlowPreviewProfile => !!p),
    canonicalDocument,
  );
  if (!containsPath(profile.root, await realpath(profile.entry))) {
    throw new Error(l10nMsg("The Flow entrypoint must be inside its project root."));
  }
  return profile;
}

function escapeHtml(value: string): string {
  return value.replace(
    /[&<>"']/g,
    (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!,
  );
}

/** Adapt the existing component-range event to saved Flow source coordinates. */
export async function revealSharedSource(
  profile: FlowPreviewProfile,
  value: unknown,
  column: vscode.ViewColumn,
): Promise<void> {
  const jump = value as PreviewSourceJump | null;
  const validPosition = (position: unknown): position is [number, number] =>
    Array.isArray(position) &&
    position.length === 2 &&
    position.every((part) => Number.isSafeInteger(part) && part >= 0);
  if (
    !vscode.workspace.isTrusted ||
    !jump ||
    typeof jump.filepath !== "string" ||
    !path.isAbsolute(jump.filepath) ||
    !validPosition(jump.start) ||
    !validPosition(jump.end)
  )
    return;
  const file = await realpath(jump.filepath);
  if (!containsPath(profile.root, file)) return;
  const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(file));
  if (doc.isDirty) {
    void vscode.window.showWarningMessage(
      l10nMsg("Save this source file before navigating from the saved Flow preview."),
    );
    return;
  }
  const toUtf16 = ([line, character]: [number, number]): [number, number] | undefined => {
    if (line >= doc.lineCount) return;
    const scalars = Array.from(doc.lineAt(line).text);
    if (character > scalars.length) return;
    return [line, scalars.slice(0, character).join("").length];
  };
  const start = toUtf16(jump.start);
  const end = toUtf16(jump.end);
  if (!start || !end) return;
  await revealPreviewSource({ filepath: file, start, end }, { document: doc, viewColumn: column });
}

export function sharedReaderHtml(url: string): string {
  const reader = new URL(url);
  const nonce = globalThis.crypto.randomUUID();
  const origin = escapeHtml(new URL(url).origin);
  return `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; frame-src ${origin}; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'">
<style>html,body{height:100%;margin:0}body{display:flex;flex-direction:column;background:var(--vscode-editor-background);color:var(--vscode-editor-foreground);font:12px var(--vscode-font-family)}header{display:flex;align-items:center;gap:8px;padding:8px}p{margin:0;flex:1}button{cursor:pointer;color:var(--vscode-button-foreground);background:var(--vscode-button-background);border:0;padding:6px 10px}iframe{flex:1;min-height:0;width:100%;border:0}</style></head><body>
<header><p>${escapeHtml(l10nMsg("Shared Flow preview · Saved files only. Save your changes to update this view."))}</p>
<button id="open-browser" type="button">${escapeHtml(l10nMsg("Open in Browser"))}</button></header>
<iframe id="reader" src="${escapeHtml(reader.toString())}" title="${escapeHtml(l10nMsg("Shared Flow preview"))}" allow="clipboard-write"></iframe>
<script nonce="${nonce}">
const vscode = acquireVsCodeApi();
document.getElementById("open-browser").addEventListener("click", () => vscode.postMessage({type: "openBrowser"}));
</script></body></html>`;
}

const panels = new Map<string, vscode.WebviewPanel>();
const opening = new Map<string, Promise<void>>();
interface SharedEditorSession {
  profile: FlowPreviewProfile;
  url: string;
  bridge: BrowserEditorBridge;
}
const editorSessions = new Map<string, Promise<SharedEditorSession>>();

async function reportSharedPosition(
  session: SharedEditorSession,
  editor: vscode.TextEditor,
): Promise<boolean> {
  const doc = editor.document;
  if (
    !session.bridge.connected ||
    !vscode.workspace.isTrusted ||
    doc.uri.scheme !== "file" ||
    doc.isDirty ||
    !containsPath(session.profile.root, doc.uri.fsPath) ||
    editor.selections.length > 1
  )
    return false;
  const position = editor.selection.active;
  const file = await realpath(doc.uri.fsPath);
  if (
    !containsPath(session.profile.root, file) ||
    doc.isDirty ||
    !position.isEqual(editor.selection.active)
  )
    return false;
  const { line, character } = position;
  return session.bridge.send({
    event: "panelScrollTo",
    filepath: file,
    line,
    character: Array.from(doc.lineAt(line).text.slice(0, character)).length,
  });
}

/** The normal manual sync command also routes through the shared control protocol. */
export async function syncSharedFlowPreview(editor: vscode.TextEditor): Promise<boolean> {
  let matched = false;
  for (const pending of editorSessions.values()) {
    const session = await pending;
    if (!containsPath(session.profile.root, editor.document.uri.fsPath)) continue;
    matched = true;
    await reportSharedPosition(session, editor);
  }
  return matched;
}

async function editorReaderSession(
  context: vscode.ExtensionContext,
  profile: FlowPreviewProfile,
  readerUrl: string,
  column: vscode.ViewColumn,
): Promise<SharedEditorSession> {
  const key = JSON.stringify([profile.id, profile.root, readerUrl]);
  const existing = editorSessions.get(key);
  if (existing) return existing;
  const pending = (async () => {
    const channel = globalThis.crypto.randomUUID();
    const bridge = await createBrowserEditorBridge(
      `http://127.0.0.1:${profile.port}/`,
      channel,
      (jump) => revealSharedSource(profile, jump, column),
    );
    try {
      const url = new URL(readerUrl);
      const endpoint = new URL(readerUrl);
      endpoint.pathname = `${endpoint.pathname.replace(/\/$/, "")}/editor/${channel}`;
      url.searchParams.set("tinymist-editor", channel);
      url.searchParams.set("tinymist-editor-control", endpoint.toString());
      const session = { profile, url: url.toString(), bridge };
      const tracker = new PreviewSelectionTracker();
      const listener = vscode.window.onDidChangeTextEditorSelection((event) => {
        const mode =
          ScrollSyncModeEnum[getPreviewConfCompat<ScrollSyncMode>("scrollSync") || "never"];
        if (
          !shouldSyncPreview(event.kind, mode) ||
          !containsPath(profile.root, event.textEditor.document.uri.fsPath) ||
          event.textEditor.document.isDirty ||
          !tracker.shouldReport(event.textEditor)
        )
          return;
        void reportSharedPosition(session, event.textEditor).catch(() => {});
      });
      context.subscriptions.push({
        dispose() {
          listener.dispose();
          bridge.dispose();
          editorSessions.delete(key);
        },
      });
      return session;
    } catch (error) {
      bridge.dispose();
      throw error;
    }
  })();
  editorSessions.set(key, pending);
  try {
    return await pending;
  } catch (error) {
    editorSessions.delete(key);
    throw error;
  }
}

/** Open a reader only; this never starts, stops, or compiles a Flow service. */
export async function openSharedFlowPreview(
  context: vscode.ExtensionContext,
  document: vscode.TextDocument,
  kind: "browser" | "webview",
): Promise<{ message: string; profileId: string }> {
  if (!vscode.workspace.isTrusted) {
    throw new Error(l10nMsg("Shared Flow preview requires a trusted workspace."));
  }
  const profile = await resolveProfile(document.uri.fsPath);
  const key = JSON.stringify([
    profile.id,
    profile.root,
    profile.entry,
    profile.port,
    profile.publicURL,
  ]);
  const existing = panels.get(key);
  if (kind === "webview" && existing) {
    existing.reveal();
    return { message: "shared", profileId: profile.id };
  }
  let pending = opening.get(key);
  if (!pending || kind === "browser") {
    pending = (async () => {
      const local = `http://127.0.0.1:${profile.port}/`;
      try {
        const response = await fetch(local, {
          signal: AbortSignal.timeout(3000),
          redirect: "error",
        });
        await response.body?.cancel();
        if (!response.ok) throw new Error(String(response.status));
      } catch {
        throw new Error(
          l10nMsg(
            "The shared Flow preview is unavailable. Start this project in Lagrangian and try again.",
          ),
        );
      }
      const url =
        vscode.env.remoteName || !profile.publicURL
          ? (await vscode.env.asExternalUri(vscode.Uri.parse(local))).toString()
          : profile.publicURL;
      const editorColumn = vscode.window.activeTextEditor?.viewColumn ?? vscode.ViewColumn.One;
      const session = await editorReaderSession(context, profile, url, editorColumn);
      if (kind === "browser") {
        if (!(await vscode.env.openExternal(vscode.Uri.parse(session.url)))) {
          throw new Error(l10nMsg("VS Code could not open the shared Flow preview URL."));
        }
        return;
      }
      const panel = vscode.window.createWebviewPanel(
        "tinymist-flow-preview",
        `${profile.name} (${l10nMsg("Saved Flow Preview")})`,
        vscode.ViewColumn.Beside,
        { enableScripts: true, retainContextWhenHidden: true, localResourceRoots: [] },
      );
      const browserAction = panel.webview.onDidReceiveMessage(async (message: unknown) => {
        const event = message as { type?: unknown } | null;
        if (event?.type !== "openBrowser") return;
        try {
          if (await vscode.env.openExternal(vscode.Uri.parse(session.url))) return;
        } catch {
          // Report browser failures without exposing forwarded URL credentials.
        }
        void vscode.window.showErrorMessage(
          l10nMsg("VS Code could not open the shared Flow preview URL."),
        );
      });
      panels.set(key, panel);
      panel.onDidDispose(() => {
        browserAction.dispose();
        if (panels.get(key) === panel) panels.delete(key);
      });
      context.subscriptions.push(panel);
      panel.webview.html = sharedReaderHtml(session.url);
    })();
    if (kind === "webview") opening.set(key, pending);
  }
  try {
    await pending;
    panels.get(key)?.reveal();
  } finally {
    if (opening.get(key) === pending) opening.delete(key);
  }
  return { message: "shared", profileId: profile.id };
}
