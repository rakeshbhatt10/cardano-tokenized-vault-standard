import { readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { sha256 } from "./hashing.ts";

export interface FactoryBuildManifest {
  schema: string; compiler: string; sources: Record<string, string>; buildScriptSha256: string;
  blueprintSha256: string; checksSha256: string; summary: { failed: number; [field: string]: unknown };
  configLock: string; [field: string]: unknown;
}
export interface FactoryBlueprint {
  validators: { title: string; parameters?: unknown[]; compiledCode: string; hash?: string }[];
  [field: string]: unknown;
}
interface SourceSelection {
  schema: string;
  originalBuildId: string;
  activeSources: string[];
  bindings: Record<string, { currentPath: string; sha256: string }>;
  excludedSources: Record<string, { sha256: string; reason: string }>;
  validatorTitles: string[];
  factoryChecks: number;
}
const exampleRoot = fileURLToPath(new URL("../../../../../", import.meta.url));
const referenceRoot = fileURLToPath(new URL("../../", new URL("../../../../../", import.meta.url)));
const originalBuildId = "3df02869565300878e93bcf267e1ed09367388a0e094ff2268e8d58c2b36e4fa";
const selectionSha256 = "f91c65231be429f5f25369f26672d337b1aff33940b63e0f2d85ffc33602d695";

function sourceSelection(): SourceSelection {
  const bytes = readFileSync(join(exampleRoot, "evidence/factory/source-selection.json"));
  if (sha256(bytes) !== selectionSha256) throw Error("Unrecognized current source selection");
  const selection = JSON.parse(bytes.toString()) as SourceSelection;
  if (selection.schema !== "CTVS-STAKING-ACTIVE-SOURCES-2" || selection.originalBuildId !== originalBuildId) throw Error("Invalid source selection origin");
  return selection;
}
/** Source labels in the deployed attestation remain immutable. Explicit current
 * path/hash bindings describe the module rename; no removed source is accepted. */
export function readFactorySource(originalPath: string) {
  const binding = sourceSelection().bindings[originalPath];
  if (!binding) throw Error("Source is not part of the current staking implementation");
  const path = binding.currentPath;
  if (path.split("/").includes("..") || path.startsWith("/")) throw Error("Invalid source path");
  if (path.startsWith("onchain/factory/") || path.startsWith("onchain/vault/lib/")) return readFileSync(join(exampleRoot, path));
  if (path.startsWith("reference:packages/onchain/lib/ctvs/")) return readFileSync(join(referenceRoot, path.slice("reference:".length)));
  throw Error("Unrecognized current source binding");
}
function inventory(directory: string, root = directory): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    if (entry.isSymbolicLink()) throw Error("Unexpected source symlink");
    const path = join(directory, entry.name);
    return entry.isDirectory() ? inventory(path, root) : [relative(root, path)];
  });
}
function verifySelection(manifest: FactoryBuildManifest, selection: SourceSelection) {
  const all = [...selection.activeSources, ...Object.keys(selection.excludedSources)];
  if (new Set(all).size !== all.length || JSON.stringify(all.sort()) !== JSON.stringify(Object.keys(manifest.sources).sort())) throw Error("Incomplete or duplicate source selection");
  if (JSON.stringify(Object.keys(selection.bindings).sort()) !== JSON.stringify([...selection.activeSources].sort())) throw Error("Incomplete current source bindings");
  for (const [path, excluded] of Object.entries(selection.excludedSources)) {
    if (manifest.sources[path] !== excluded.sha256) throw Error("Excluded source origin mismatch");
  }
  const activeSources: Record<string, string> = {};
  const paths = new Set<string>();
  for (const originalPath of selection.activeSources) {
    const binding = selection.bindings[originalPath];
    if (!manifest.sources[originalPath] || !binding || paths.has(binding.currentPath) || sha256(readFactorySource(originalPath)) !== binding.sha256) throw Error("Stale or duplicate current source binding: " + originalPath);
    paths.add(binding.currentPath);
    activeSources[originalPath] = binding.sha256;
  }
  for (const directory of ["onchain/factory", "onchain/vault/lib"]) {
    const expected = [...paths].filter(path => path.startsWith(directory + "/")).map(path => path.slice(directory.length + 1)).sort();
    if (JSON.stringify(inventory(join(exampleRoot, directory)).sort()) !== JSON.stringify(expected)) throw Error("Current source inventory changed: " + directory);
  }
  return activeSources;
}
/** Authenticate original deployment evidence and renamed current sources.
 * The rebuild command proves every retained validator's exact deployed bytes. */
export function readVerifiedFactoryBuild() {
  const directory = join(exampleRoot, "evidence/factory");
  const manifestBytes = readFileSync(join(directory, "build.json"));
  if (sha256(manifestBytes) !== originalBuildId) throw Error("Unrecognized factory attestation");
  const manifest = JSON.parse(manifestBytes.toString()) as FactoryBuildManifest;
  if (manifest.schema !== "FACTORY-IDENTITY-PROOF-BUILD-1" || manifest.compiler !== "aiken v1.1.22+39d6b04" || manifest.summary.failed !== 0) throw Error("Invalid factory build");
  const selection = sourceSelection();
  const activeSources = verifySelection(manifest, selection);
  const blueprintBytes = readFileSync(join(directory, "blueprint.json"));
  if (sha256(blueprintBytes) !== manifest.blueprintSha256 || sha256(readFileSync(join(directory, "checks.json"))) !== manifest.checksSha256 || sha256(readFileSync(join(directory, "original-build-script.ts"))) !== manifest.buildScriptSha256) throw Error("Altered factory evidence");
  const blueprint = JSON.parse(blueprintBytes.toString()) as FactoryBlueprint;
  return { manifest, blueprint, buildId: originalBuildId, activeSources, sourceSelection: selection, sourceSelectionSha256: selectionSha256 };
}
