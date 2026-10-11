import * as vscode from "vscode";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { createBrowserEditorBridge } from "../../features/shared-flow-browser";
import { WebSocket } from "ws";
import { once } from "node:events";
import { revealSharedSource } from "../../features/shared-flow-preview";
import type { Context } from ".";

export async function getTests(ctx: Context) {
  ctx = ctx.workspaceCtx("book");
  await ctx.suite("shared Flow routing", async (suite) => {
    suite.addTest(
      "external browser control protocol reveals a Unicode component range in the running editor",
      async () => {
        const root = ctx.workspaceUri();
        const target = vscode.Uri.joinPath(root, "shared-browser-navigation.typ");
        await writeFile(target.fsPath, "= Browser navigation\n한😀글 source target\n");
        const profile = {
          id: "browser",
          name: "Browser",
          root: root.fsPath,
          entry: target.fsPath,
          port: 23625,
          publicURL: "",
        };
        const bridge = await createBrowserEditorBridge(
          "http://localhost:23625",
          "browser-session",
          (hit) => revealSharedSource(profile, hit, vscode.ViewColumn.One),
        );
        const connection = new WebSocket(bridge.localUrl.replace(/^http/, "ws"), {
          origin: "http://localhost:23625",
        });
        try {
          await once(connection, "open");
          connection.send(
            JSON.stringify({
              event: "editorScrollTo",
              filepath: target.fsPath,
              start: [1, 3],
              end: [1, 6],
            }),
          );
          const deadline = Date.now() + 5000;
          while (
            vscode.window.activeTextEditor?.document.uri.toString() !== target.toString() &&
            Date.now() < deadline
          )
            await ctx.timeout(50);
          const editor = vscode.window.activeTextEditor;
          ctx.expect(editor?.document.uri.toString()).to.equal(target.toString());
          ctx.expect(editor?.selection.active.line).to.equal(1);
          ctx.expect(editor?.selection.start.character).to.equal(4);
          ctx.expect(editor?.selection.end.character).to.equal(7);
        } finally {
          connection.terminate();
          bridge.dispose();
          await vscode.commands.executeCommand("workbench.action.closeAllEditors");
          await rm(target.fsPath, { force: true });
        }
      },
    );
    suite.addTest("normal preview command reuses Flow without an LSP preview task", async () => {
      const root = ctx.workspaceUri();
      const support = await mkdtemp(path.join(tmpdir(), "flow-preview-test-"));
      const previousSupport = process.env.FLOW_DATA_DIR;
      const config = vscode.workspace.getConfiguration("tinymist");
      const previous = config.get<boolean>("preview.sharedFlow");
      let readerRequests = 0;
      let panelScroll: any;
      const target = vscode.Uri.joinPath(root, "shared-navigation.typ");
      const http = createServer(async (request, response) => {
        if (request.url === "/scroll" && request.method === "POST") {
          let body = "";
          for await (const chunk of request) body += chunk;
          panelScroll = JSON.parse(body);
          response.writeHead(204).end();
          return;
        }
        readerRequests += 1;
        response.writeHead(200, { "Content-Type": "text/html" });
        response.end(`<!doctype html><title>Shared fixture</title><p>Saved fixture</p>
          <script>
          const endpoint = new URL(new URL(location.href).searchParams.get("tinymist-editor-control"));
          endpoint.protocol = endpoint.protocol === "https:" ? "wss:" : "ws:";
          const editor = new WebSocket(endpoint);
          editor.addEventListener("open", () => editor.send(JSON.stringify({event: "editorScrollTo",
            filepath: ${JSON.stringify(target.fsPath)}, start: [1,3], end: [1,6]})));
          editor.addEventListener("message", async event => {
            const data = await event.data.text();
            fetch("/scroll", {method: "POST", body: data});
          });
          </script>`);
      });
      await new Promise<void>((resolve) => http.listen(0, "127.0.0.1", resolve));
      try {
        await writeFile(target.fsPath, "= Navigation\n한😀글 source target\n");
        process.env.FLOW_DATA_DIR = support;
        const port = (http.address() as AddressInfo).port;
        await writeFile(
          path.join(support, "profiles.json"),
          JSON.stringify({
            schemaVersion: 1,
            profiles: [
              {
                id: "test",
                name: "Shared fixture",
                root: root.fsPath,
                entry: "main.typ",
                port,
                publicURL: "",
              },
            ],
          }),
        );
        await ctx.openDocument(vscode.Uri.joinPath(root, "main.typ"));
        await vscode.extensions.getExtension("myriad-dreamin.tinymist")!.activate();
        await config.update("preview.sharedFlow", true, vscode.ConfigurationTarget.Global);
        const before = await vscode.commands.executeCommand<{ tasks: unknown[] }>(
          "tinymist.doInspectPreviewState",
        );
        for (let i = 0; i < 2; i++) {
          const result = await vscode.commands.executeCommand<{
            message: string;
            profileId: string;
          }>("typst-preview.preview");
          ctx.expect(result?.message).to.equal("shared");
          ctx.expect(result?.profileId).to.equal("test");
          if (i === 0) await ctx.openDocument(vscode.Uri.joinPath(root, "main.typ"));
        }
        const deadline = Date.now() + 5000;
        while (readerRequests < 2 && Date.now() < deadline) await ctx.timeout(50);
        ctx.expect(readerRequests).to.be.at.least(2); // health probe plus actual iframe
        const navigationDeadline = Date.now() + 5000;
        while (
          vscode.window.activeTextEditor?.document.uri.toString() !== target.toString() &&
          Date.now() < navigationDeadline
        )
          await ctx.timeout(50);
        const editor = vscode.window.activeTextEditor;
        ctx.expect(editor?.document.uri.toString()).to.equal(target.toString());
        ctx.expect(editor?.selection.active.line).to.equal(1);
        ctx.expect(editor?.selection.start.character).to.equal(4);
        ctx.expect(editor?.selection.end.character).to.equal(7);
        ctx.expect(panelScroll).to.equal(undefined); // Command reveal never feeds back.
        await vscode.commands.executeCommand("typst-preview.sync");
        const syncDeadline = Date.now() + 5000;
        while (!panelScroll && Date.now() < syncDeadline) await ctx.timeout(50);
        ctx
          .expect(panelScroll)
          .to.deep.equal({
            event: "panelScrollTo",
            filepath: target.fsPath,
            line: 1,
            character: 6,
          });
        const after = await vscode.commands.executeCommand<{ tasks: unknown[] }>(
          "tinymist.doInspectPreviewState",
        );
        ctx.expect(after?.tasks).to.deep.equal(before?.tasks);
        // A still-serving endpoint verifies that viewer disposal does not stop the service.
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
        ctx.expect((await fetch(`http://127.0.0.1:${port}/`)).status).to.equal(200);
      } finally {
        await config.update("preview.sharedFlow", previous, vscode.ConfigurationTarget.Global);
        if (previousSupport === undefined) delete process.env.FLOW_DATA_DIR;
        else process.env.FLOW_DATA_DIR = previousSupport;
        http.closeAllConnections();
        await new Promise<void>((resolve) => http.close(() => resolve()));
        await rm(support, { recursive: true, force: true });
        await rm(target.fsPath, { force: true });
      }
    });
  });
}
