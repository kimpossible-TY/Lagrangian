import { runInNewContext } from "node:vm";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import type * as vscode from "vscode";

const mock = vi.hoisted(() => ({
  readFile: vi.fn(),
  realpath: vi.fn(),
  fetch: vi.fn(),
  createWebviewPanel: vi.fn(),
  asExternalUri: vi.fn(),
  openExternal: vi.fn(),
  workspace: { isTrusted: true },
  remoteName: undefined as string | undefined,
  showErrorMessage: vi.fn(),
  showWarningMessage: vi.fn(),
  openTextDocument: vi.fn(),
  showTextDocument: vi.fn(),
}));
vi.mock("node:fs/promises", () => ({ readFile: mock.readFile, realpath: mock.realpath }));
vi.mock("vscode", () => ({
  workspace: {
    get isTrusted() {
      return mock.workspace.isTrusted;
    },
    openTextDocument: mock.openTextDocument,
  },
  window: {
    createWebviewPanel: mock.createWebviewPanel,
    showErrorMessage: mock.showErrorMessage,
    showWarningMessage: mock.showWarningMessage,
    showTextDocument: mock.showTextDocument,
    visibleTextEditors: [],
  },
  env: {
    asExternalUri: mock.asExternalUri,
    openExternal: mock.openExternal,
    get remoteName() {
      return mock.remoteName;
    },
  },
  Uri: {
    parse: (url: string) => ({ toString: () => url }),
    file: (file: string) => ({ fsPath: file, toString: () => `file://${file}` }),
  },
  Position: class {
    constructor(
      public line: number,
      public character: number,
    ) {}
  },
  Range: class {
    constructor(
      public start: unknown,
      public end: unknown,
    ) {}
  },
  TextEditorRevealType: { InCenterIfOutsideViewport: 2 },
  ViewColumn: { Beside: 2 },
}));
vi.mock("../l10n", () => ({ l10nMsg: (message: string) => message }));
import {
  containsPath,
  openSharedFlowPreview,
  parseFlowProfiles,
  selectFlowProfile,
  sharedReaderHtml,
  revealSharedSource,
} from "./shared-flow-preview";

const profile = {
  id: "book",
  name: "Book",
  root: "/project",
  entry: "main.typ",
  port: 23625,
  publicURL: "https://reader.example/",
};
let contexts: Array<{ subscriptions: Array<{ dispose(): void }> }> = [];
function context() {
  const ctx = { subscriptions: [] as Array<{ dispose(): void }> };
  contexts.push(ctx);
  return ctx as unknown as vscode.ExtensionContext;
}
const document = { uri: { fsPath: "/project/chapter.typ" } } as vscode.TextDocument;

beforeEach(() => {
  vi.clearAllMocks();
  mock.workspace.isTrusted = true;
  mock.remoteName = undefined;
  mock.readFile.mockResolvedValue(JSON.stringify({ schemaVersion: 1, profiles: [profile] }));
  mock.realpath.mockImplementation(async (file: string) => file);
  mock.fetch.mockResolvedValue({ ok: true, body: { cancel: vi.fn() } });
  vi.stubGlobal("fetch", mock.fetch);
  mock.asExternalUri.mockResolvedValue({
    toString: () => "https://forwarded.example/?token=a&b=c",
  });
  mock.openExternal.mockResolvedValue(true);
  mock.createWebviewPanel.mockImplementation(() => {
    let disposed = () => {};
    return {
      webview: { html: "", onDidReceiveMessage: vi.fn(() => ({ dispose: vi.fn() })) },
      reveal: vi.fn(),
      onDidDispose: (callback: () => void) => {
        disposed = callback;
      },
      dispose: () => disposed(),
    };
  });
});
afterEach(() => {
  contexts.forEach((ctx) => ctx.subscriptions.forEach((item) => item.dispose()));
  contexts = [];
  vi.unstubAllGlobals();
});

test("profile matching respects directory boundaries and selects the deepest root", () => {
  expect(containsPath("/project", "/project-other/main.typ")).toBe(false);
  const profiles = parseFlowProfiles({
    schemaVersion: 1,
    profiles: [profile, { ...profile, id: "nested", root: "/project/sub" }],
  });
  expect(selectFlowProfile(profiles, "/project/sub/child.typ").id).toBe("nested");
  expect(() => selectFlowProfile([profiles[0], profiles[0]], "/project/main.typ")).toThrow(
    "Multiple",
  );
  expect(() => selectFlowProfile(profiles, "/unmanaged/main.typ")).toThrow("No Flow profile");
});

test.each([
  { entry: "../outside.typ" },
  { publicURL: "http://reader.example/" },
  { publicURL: "https://user:secret@reader.example/" },
  { publicURL: "https://reader.example/path" },
  { port: 99999 },
  { root: "relative" },
])("rejects invalid profile fields %j", (change) => {
  expect(() =>
    parseFlowProfiles({ schemaVersion: 1, profiles: [{ ...profile, ...change }] }),
  ).toThrow();
});

test("concurrent and repeated opens share one viewer and use the public route directly", async () => {
  const ctx = context();
  await Promise.all(
    Array.from({ length: 8 }, () => openSharedFlowPreview(ctx, document, "webview")),
  );
  await openSharedFlowPreview(ctx, document, "webview");
  expect(mock.createWebviewPanel).toHaveBeenCalledTimes(1);
  expect(mock.fetch).toHaveBeenCalledTimes(1);
  expect(mock.asExternalUri).not.toHaveBeenCalled();
  expect(mock.createWebviewPanel.mock.results[0].value.webview.html).toContain(
    "https://reader.example/",
  );
  expect(mock.createWebviewPanel.mock.results[0].value.webview.html).toContain("Saved files only");
});

test("closing only the viewer permits reopening without a service mutation", async () => {
  const ctx = context();
  await openSharedFlowPreview(ctx, document, "webview");
  ctx.subscriptions[0].dispose();
  await openSharedFlowPreview(ctx, document, "webview");
  expect(mock.createWebviewPanel).toHaveBeenCalledTimes(2);
  expect(mock.fetch.mock.calls.every(([, opts]) => opts.method === undefined)).toBe(true);
});

test("loopback-only profiles use port forwarding and preserve the full forwarded URL", async () => {
  mock.readFile.mockResolvedValue(
    JSON.stringify({ schemaVersion: 1, profiles: [{ ...profile, publicURL: "" }] }),
  );
  await openSharedFlowPreview(context(), document, "webview");
  expect(mock.asExternalUri).toHaveBeenCalledTimes(1);
  expect(mock.createWebviewPanel.mock.results[0].value.webview.html).toContain("?token=a&amp;b=c");
});

test("untrusted workspaces cannot read host profiles", async () => {
  mock.workspace.isTrusted = false;
  await expect(openSharedFlowPreview(context(), document, "webview")).rejects.toThrow("trusted");
  expect(mock.readFile).not.toHaveBeenCalled();
});

test("an unavailable service fails without a viewer and can be retried", async () => {
  mock.fetch.mockRejectedValueOnce(new Error("refused"));
  const ctx = context();
  await expect(openSharedFlowPreview(ctx, document, "webview")).rejects.toThrow(
    "Start this project",
  );
  expect(mock.createWebviewPanel).not.toHaveBeenCalled();
  await openSharedFlowPreview(ctx, document, "webview");
  expect(mock.createWebviewPanel).toHaveBeenCalledTimes(1);
});

test("canonical paths prevent symlink entrypoints outside the profile", async () => {
  mock.realpath.mockImplementation(async (file: string) =>
    file === "/project/main.typ" ? "/outside/main.typ" : file,
  );
  await expect(openSharedFlowPreview(context(), document, "webview")).rejects.toThrow("inside");
  expect(mock.fetch).not.toHaveBeenCalled();
});

test("external browser opening reports failure", async () => {
  mock.openExternal.mockResolvedValue(false);
  await expect(openSharedFlowPreview(context(), document, "browser")).rejects.toThrow(
    "could not open",
  );
  expect(mock.createWebviewPanel).not.toHaveBeenCalled();
});

test("reader CSP is limited to its origin and URL attributes are escaped", () => {
  const html = sharedReaderHtml("https://reader.example/?x=%22&y=1");
  expect(html).toContain("default-src 'none'; frame-src https://reader.example;");
  expect(html).toContain("x=%22&amp;y=1");
});

test("remote readers use tunnel forwarding even with a private public URL", async () => {
  mock.remoteName = "tunnel";
  await openSharedFlowPreview(context(), document, "webview");
  const panel = mock.createWebviewPanel.mock.results[0].value;
  expect(mock.asExternalUri).toHaveBeenCalledTimes(1);
  expect(panel.webview.html).toContain("https://forwarded.example/?token=a&amp;b=c");
  expect(panel.webview.html).not.toContain("https://reader.example/");
  expect(panel.webview.html).toContain("Open in Browser");
  const handler = panel.webview.onDidReceiveMessage.mock.calls[0][0];
  await handler({ type: "openBrowser", url: "https://untrusted.example/" });
  const external = new URL(String(mock.openExternal.mock.calls[0][0].toString()));
  expect(external.origin).toBe("https://forwarded.example");
  expect(external.searchParams.get("token")).toBe("a");
  expect(external.searchParams.get("tinymist-editor-callback")).toBe(
    "https://forwarded.example/?token=a&b=c",
  );
  await handler({ type: "unknown" });
  expect(mock.openExternal).toHaveBeenCalledTimes(1);
  mock.openExternal.mockResolvedValue(false);
  await handler({ type: "openBrowser" });
  expect(mock.showErrorMessage).toHaveBeenCalledWith(expect.stringContaining("could not open"));
});

const sourceHit = { filepath: "/project/chapter.typ", line: 2, column: 4 };
function mockSource(isDirty = false) {
  const doc = {
    isDirty,
    lineCount: 3,
    uri: { toString: () => "file:///project/chapter.typ" },
    lineAt: () => ({ text: "한😀글 source" }),
  };
  mock.openTextDocument.mockResolvedValue(doc);
  const editor = { revealRange: vi.fn() };
  mock.showTextDocument.mockResolvedValue(editor);
  return editor;
}
const canonicalProfile = { ...profile, entry: "/project/main.typ" };
test("source hits open the source group with an exact UTF-16 cursor position", async () => {
  const editor = mockSource();
  await revealSharedSource(canonicalProfile, sourceHit, 1);
  const opts = mock.showTextDocument.mock.calls[0][1];
  expect(opts.viewColumn).toBe(1);
  expect(opts.preserveFocus).toBe(false);
  expect(opts.selection.start).toEqual({ line: 1, character: 4 });
  expect(opts.selection.end).toEqual(opts.selection.start);
  expect(editor.revealRange).toHaveBeenCalled();
});

test("untrusted, invalid and canonical outside-project hits cannot open files", async () => {
  mockSource();
  for (const change of [
    { filepath: "../secret" },
    { line: 0 },
    { column: 1.5 },
    { filepath: "/project-other/secret" },
  ]) {
    await revealSharedSource(canonicalProfile, { ...sourceHit, ...change }, 1);
  }
  mock.realpath.mockResolvedValueOnce("/outside/symlink-target.typ");
  await revealSharedSource(canonicalProfile, sourceHit, 1);
  mock.workspace.isTrusted = false;
  await revealSharedSource(canonicalProfile, sourceHit, 1);
  expect(mock.openTextDocument).not.toHaveBeenCalled();
});

test("dirty sources and out-of-range positions do not move the cursor", async () => {
  mockSource(true);
  await revealSharedSource(canonicalProfile, sourceHit, 1);
  expect(mock.showWarningMessage).toHaveBeenCalled();
  mockSource(false);
  await revealSharedSource(canonicalProfile, { ...sourceHit, line: 99 }, 1);
  await revealSharedSource(canonicalProfile, { ...sourceHit, column: 99 }, 1);
  expect(mock.showTextDocument).not.toHaveBeenCalled();
});

test("webview bridge rejects messages from another iframe, origin or panel", () => {
  const channel = "12345678-1234-1234-1234-123456789abc";
  const html = sharedReaderHtml("https://reader.example/?token=keep", channel);
  const script = html.match(/<script nonce="[^"]+">([\s\S]*?)<\/script>/)![1];
  const frame = {
    src: `https://reader.example/?token=keep&tinymist-editor=${channel}`,
    contentWindow: {},
  };
  const postMessage = vi.fn();
  let listener: (event: unknown) => void = () => {};
  runInNewContext(script, {
    URL,
    acquireVsCodeApi: () => ({ postMessage }),
    document: {
      getElementById: (id: string) => (id === "reader" ? frame : { addEventListener() {} }),
    },
    window: {
      addEventListener: (_name: string, handler: typeof listener) => {
        listener = handler;
      },
    },
  });
  const data = { type: "flowSourceLocation", channel, ...sourceHit };
  const valid = { source: frame.contentWindow, origin: "https://reader.example", data };
  listener({ ...valid, source: {} });
  listener({ ...valid, origin: "https://attacker.example" });
  listener({ ...valid, data: { ...data, channel: "other" } });
  expect(postMessage).not.toHaveBeenCalled();
  listener(valid);
  expect(postMessage).toHaveBeenCalledWith(data);
});
