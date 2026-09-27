import { existsSync } from "node:fs";
import esbuild from "esbuild";

const production = process.argv.includes("--production");
const watch = process.argv.includes("--watch");

const common = { bundle: true, sourcemap: !production, minify: production };

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
