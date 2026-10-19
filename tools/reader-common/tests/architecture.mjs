import assert from "node:assert/strict";
import test from "node:test";
import { readdir, readFile, realpath } from "node:fs/promises";
import { dirname, extname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";

const tools = fileURLToPath(new URL("../../", import.meta.url));
const roots = {
  shared: resolve(tools, "reader-common"),
  html: resolve(tools, "flow-reader/web"),
  paged: resolve(tools, "typst-preview-frontend/src"),
  dom: resolve(tools, "typst-dom/src"),
};
const within = (file, root) => file === root || file.startsWith(root + "/");
const owner = (file) => Object.entries(roots).find(([, root]) => within(file, root))?.[0];

async function sourceFiles(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (["vendor", "tests"].includes(entry.name) || entry.isSymbolicLink()) continue;
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) files.push(...(await sourceFiles(path)));
    else if (
      [".js", ".ts", ".mts"].includes(extname(path)) &&
      !path.endsWith(".d.ts") &&
      !path.endsWith(".test.ts") &&
      !path.endsWith(".test.mts")
    )
      files.push(path);
  }
  return files;
}

function imports(source, filename) {
  const file = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
  const found = [];
  function visit(node) {
    if (ts.isImportDeclaration(node)) {
      if (!node.importClause?.isTypeOnly && ts.isStringLiteral(node.moduleSpecifier))
        found.push(node.moduleSpecifier.text);
    } else if (ts.isExportDeclaration(node)) {
      if (!node.isTypeOnly && node.moduleSpecifier && ts.isStringLiteral(node.moduleSpecifier))
        found.push(node.moduleSpecifier.text);
    } else if (
      ts.isCallExpression(node) &&
      node.expression.kind === ts.SyntaxKind.ImportKeyword &&
      ts.isStringLiteral(node.arguments[0])
    ) {
      found.push(node.arguments[0].text);
    }
    ts.forEachChild(node, visit);
  }
  visit(file);
  return found;
}

async function dependencyGraph() {
  const graph = new Map();
  for (const root of Object.values(roots)) {
    for (const file of await sourceFiles(root)) {
      const dependencies = [];
      for (const specifier of imports(await readFile(file, "utf8"), file)) {
        if (!specifier.startsWith(".")) continue;
        const target = resolve(dirname(file), specifier);
        for (const candidate of [
          target,
          target + ".ts",
          target + ".js",
          ...(target.endsWith(".mjs") ? [target.slice(0, -4) + ".mts"] : []),
        ]) {
          try {
            const actual = await realpath(candidate);
            if (owner(actual)) dependencies.push(actual);
            break;
          } catch {
            // Extensionless TypeScript and native ESM use distinct resolution rules.
          }
        }
      }
      graph.set(file, dependencies);
    }
  }
  return graph;
}

const graph = await dependencyGraph();
test("shared policies and renderer adapters preserve reader dependency boundaries", () => {
  assert.ok(graph.size > 40, "the actual first-party reader graph must be inspected");
  for (const [file, dependencies] of graph) {
    for (const dependency of dependencies) {
      const from = owner(file),
        to = owner(dependency);
      assert.ok(
        from !== "shared" || to === "shared",
        `shared policy imports concrete reader: ${relative(tools, file)}`,
      );
      assert.ok(
        from === "shared" || to === "shared" || from === to || (from === "paged" && to === "dom"),
        `cross-reader internal import: ${relative(tools, file)} -> ${relative(tools, dependency)}`,
      );
    }
  }
});

test("first-party reader modules have no runtime import cycles", () => {
  const completed = new Set();
  const active = [];
  function visit(file) {
    if (completed.has(file)) return;
    assert.ok(
      !active.includes(file),
      `reader import cycle: ${[...active, file].map((path) => relative(tools, path)).join(" -> ")}`,
    );
    active.push(file);
    for (const dependency of graph.get(file) ?? []) visit(dependency);
    active.pop();
    completed.add(file);
  }
  for (const file of graph.keys()) visit(file);
});
