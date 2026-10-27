import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import ts from "typescript";

const root = fileURLToPath(new URL("../", import.meta.url));

function files(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);

    return entry.isDirectory() ? files(path) : [path];
  });
}

function imports(path: string): string[] {
  const source = ts.createSourceFile(
    path,
    readFileSync(path, "utf8"),
    ts.ScriptTarget.Latest,
    true,
  );
  const result: string[] = [];

  const visit = (node: ts.Node) => {
    if (
      (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) &&
      node.moduleSpecifier &&
      ts.isStringLiteral(node.moduleSpecifier)
    )
      result.push(node.moduleSpecifier.text);

    if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword) {
      const argument = node.arguments[0];

      if (argument && ts.isStringLiteral(argument)) result.push(argument.text);
    }

    ts.forEachChild(node, visit);
  };

  visit(source);

  return result
    .filter((path) => path.startsWith("."))
    .map((imported) => resolve(dirname(path), imported.replace(/\.js$/, ".ts")));
}

test("every retained TypeScript module is reachable and unused upstream source trees are absent", () => {
  const modules = ["src", "vendor/client", "test"]
    .flatMap((directory) => files(join(root, directory)))
    .filter((path) => path.endsWith(".ts"));
  const known = new Set(modules);
  const commands = [
    "src/index.ts",
    "src/demo.ts",
    "src/inspect.ts",
    "src/prepare.ts",
    "src/check-contracts.ts",
  ];
  const roots = modules.filter(
    (path) => path.endsWith(".test.ts") || commands.includes(relative(root, path)),
  );
  const edges = new Map(
    modules.map((path) => [path, imports(path).filter((path) => known.has(path))]),
  );
  const reached = new Set<string>();

  const visit = (path: string) => {
    if (reached.has(path)) return;

    reached.add(path);

    for (const dependency of edges.get(path) ?? []) visit(dependency);
  };

  for (const path of roots) visit(path);

  assert.deepEqual(
    modules.filter((path) => !reached.has(path)).map((path) => relative(root, path)),
    [],
  );

  for (const path of [
    "onchain/staking/offchain",
    "onchain/staking/delivery",
    "onchain/staking/validators/token.ak",
    "vendor/client/src/factory/publication-artifacts.ts",
    "vendor/client/src/owner",
    "vendor/client/protocol/shared-v1/authorization.ak",
  ])
    assert.equal(existsSync(join(root, path)), false);
});
