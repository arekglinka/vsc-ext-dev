import { copyFileSync, existsSync, readdirSync, statSync } from "node:fs";
import esbuild from "esbuild";

const production = process.argv.includes("--production");
const watch = process.argv.includes("--watch");

const common = { bundle: true, sourcemap: !production, minify: production };

// purs-backend-es does not recopy foreign.js when only the JS changed
// (it keys on the .purs file), so sync foreign modules from output/ (which
// spago keeps fresh) into output-es/ before bundling.
function syncForeignModules() {
  if (!existsSync("output-es") || !existsSync("output")) return;
  let copied = 0;
  for (const entry of readdirSync("output-es")) {
    const esForeign = `output-es/${entry}/foreign.js`;
    const outForeign = `output/${entry}/foreign.js`;
    if (!existsSync(outForeign)) continue;
    if (!existsSync(esForeign) || statSync(esForeign).mtimeMs < statSync(outForeign).mtimeMs) {
      copyFileSync(outForeign, esForeign);
      copied += 1;
    }
  }
  if (copied > 0) console.log(`[ext] synced ${copied} foreign.js from output/ to output-es/`);
}
syncForeignModules();

const webviewEntry = "webview-src/entry.js";
const webviewReady = existsSync("output-es/Webview.Main/index.js");

if (!webviewReady) {
  console.warn(
    "[webview] output-es/Webview.Main/index.js missing — run `npm run build && npm run backend` first"
  );
}

const hostEntry = "host-src/entry.js";
const hostReady = existsSync("output-es/Host.Main/index.js");

if (!hostReady) {
  console.warn(
    "[host] output-es/Host.Main/index.js missing — run `npm run build && npm run backend` first"
  );
}

const hostCtx = hostReady
  ? await esbuild.context({
      ...common,
      entryPoints: [hostEntry],
      outfile: "dist/extension.js",
      format: "cjs",
      platform: "node",
      target: "ES2022",
      external: ["vscode"],
    })
  : null;

const webviewCtx = webviewReady
  ? await esbuild.context({
      ...common,
      entryPoints: [webviewEntry],
      outfile: "media/webview.js",
      format: "iife",
      platform: "browser",
      target: "ES2022",
    })
  : null;

if (watch) {
  if (hostCtx) {
    await hostCtx.watch();
  }
  if (webviewCtx) {
    await webviewCtx.watch();
  }
  console.log("[ext] watching…");
} else {
  if (hostCtx) {
    await hostCtx.rebuild();
    await hostCtx.dispose();
    console.log("[ext] built dist/extension.js");
  }
  if (webviewCtx) {
    await webviewCtx.rebuild();
    await webviewCtx.dispose();
    console.log("[ext] built media/webview.js");
  }
}
