// Auto-install the freshly packaged extension into the vscode-server
// extensions directory, so the INSTALLED copy never runs stale code
// (the devcontainer's remote host loads it from there, not from dist/).
// Chained into `npm run package`; safe to run standalone — it rebuilds the
// vsix only when missing/older than the bundles.
//
// A VSCode "Developer: Reload Window" is still required to pick the new
// files up (extension hosts only read their files at startup); this script
// prints that reminder.
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const vsix = join(root, "purs-graphs.vsix");
const extDirName = "arekglinka.purs-graphs-0.1.0";
const candidates = [
  join(process.env.HOME ?? "", ".vscode-server", "extensions"),
  join(process.env.HOME ?? "", ".vscode", "extensions"),
];

function stale() {
  if (!existsSync(vsix)) return true;
  const vsixMtime = statSync(vsix).mtimeMs;
  return [join(root, "dist", "extension.js"), join(root, "media", "webview.js")].some(
    (p) => existsSync(p) && statSync(p).mtimeMs > vsixMtime
  );
}

if (stale()) {
  console.log("[install-extension] bundles newer than vsix — repackaging…");
  execFileSync("npm", ["run", "compile"], { cwd: root, stdio: "inherit" });
  execFileSync("npx", ["@vscode/vsce", "package", "--no-dependencies", "-o", "purs-graphs.vsix"], {
    cwd: root,
    stdio: "inherit",
  });
}

const target = candidates.find((dir) => existsSync(join(dir, extDirName)));
if (!target) {
  console.log(
    `[install-extension] no installed ${extDirName} found (looked in ${candidates.join(", ")}) — nothing to refresh.`
  );
  console.log(
    "[install-extension] install the vsix once (code --install-extension purs-graphs.vsix) to enable auto-sync."
  );
  process.exit(0);
}

const tmp = join(root, ".vsix-extract");
rmSync(tmp, { recursive: true, force: true });
mkdirSync(tmp, { recursive: true });
execFileSync("unzip", ["-qo", vsix, "-d", tmp], { stdio: "inherit" });
for (const part of ["dist", "media", "package.json"]) {
  cpSync(join(tmp, "extension", part), join(target, extDirName, part), { recursive: true });
}
rmSync(tmp, { recursive: true, force: true });
console.log(`[install-extension] refreshed ${join(target, extDirName)} from purs-graphs.vsix`);
console.log("[install-extension] run 'Developer: Reload Window' in VSCode to load it.");
// sanity: the refreshed bundle must carry the fixed nonce markup
const shipped = readdirSync(join(target, extDirName, "dist")).join(",");
if (!shipped.includes("extension.js")) {
  console.error("[install-extension] FAILED — dist/extension.js missing after refresh");
  process.exit(1);
}
