import * as vscode from "vscode";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import type { Context } from ".";

export async function getTests(ctx: Context) {
  ctx = ctx.workspaceCtx("book");
  await ctx.suite("shared Flow routing", async (suite) => {
    suite.addTest("normal preview command reuses Flow without an LSP preview task", async () => {
      const root = ctx.workspaceUri();
      const support = await mkdtemp(path.join(tmpdir(), "flow-preview-test-"));
      const previousSupport = process.env.FLOW_DATA_DIR;
      const config = vscode.workspace.getConfiguration("tinymist");
      const previous = config.get<boolean>("preview.sharedFlow");
      let readerRequests = 0;
      const http = createServer((_request, response) => {
        readerRequests += 1;
        response.writeHead(200, { "Content-Type": "text/html" });
        response.end("<!doctype html><title>Shared fixture</title><p>Saved fixture</p>");
      });
      await new Promise<void>((resolve) => http.listen(0, "127.0.0.1", resolve));
      try {
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
          await ctx.openDocument(vscode.Uri.joinPath(root, "main.typ"));
        }
        const deadline = Date.now() + 5000;
        while (readerRequests < 2 && Date.now() < deadline) await ctx.timeout(50);
        ctx.expect(readerRequests).to.be.at.least(2); // health probe plus actual iframe
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
      }
    });
  });
}
