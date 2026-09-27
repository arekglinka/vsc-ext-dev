# AGENTS.md

## Project

`vsc-ext-dev` is the standalone repo for the **Purs Graphs** VSCode extension:
live previews of Graphviz DOT files and JSON graph specs. The extension host
and webview are both PureScript; TypeScript was fully removed. FFI bindings
to `dagre` (layout), `@viz-js/viz` (Graphviz WASM), and the VSCode API are
vendored under `packages/`.

## Stack

- PureScript 0.15.16, spago 1.x workspace (registry 61.0.0), purs-backend-es
- `packages/purs-vscode`: bindings over the VSCode API (the host's only
  access to vscode); `packages/purs-graphs-protocol`: shared host↔webview
  message protocol (ADTs + argonaut codecs, single source of truth)
- esbuild bundling (host CJS with `vscode` external, webview IIFE)
- `node:22-slim` devcontainer, single `devcontainer.json`, toolchain via `npm ci`

## Build Commands

| Command | Purpose |
|---|---|
| `npm run build` | `spago build`: compile all 6 workspace packages (vendored libs, protocol, vscode bindings, host, webview) |
| `npm run backend` | `purs-backend-es build`: `output/` corefn → `output-es/` ES modules |
| `node esbuild.mjs` | Build `dist/extension.js` + `media/webview.js` |
| `npm run compile` | `spago build` + purs-backend-es + esbuild bundles, no tsc |
| `npm test` | 5 spago packages + headless webview + host smoke tests |
| `npm run package` | compile + `vsce package` → `purs-graphs.vsix` |
| `npm run format:check` | purs-tidy (`packages webview-src host-src`) + biome gate |

## Code Style

- PureScript: 2-space, 100-col, purs-tidy (scope covers `packages`,
  `webview-src`, and `host-src`). FFI: thin JS, logic in PureScript,
  `Effect`-returning thunks, no exceptions across the boundary.
- JS tooling (scripts, vendor stub, esbuild.mjs, FFI files): biome, 2-space,
  double quotes, semicolons.
- Never suppress type errors; no `unsafeCoerce`.

## Gotchas

- **spago needs git in PATH** (even via npx): that's why the devcontainer
  pulls the git feature.
- **Two output dirs**: `spago build` → `output/` (corefn); `purs-backend-es` →
  `output-es/`. BOTH bundles import from `output-es/` (host:
  `output-es/Host.Main/index.js`, webview: `output-es/Webview.Main/index.js`).
  The esbuild guard skips either context with a warning if its module is
  missing; `npm run compile` always runs the backend first, so the guard only
  fires on out-of-order manual esbuild runs.
- **viz.js WASM is inlined** in the npm package, no `.wasm` loader config in
  esbuild; the webview CSP needs `'wasm-unsafe-eval'` (template in
  `host-src/src/Host/Html.purs`).
- **Both entries are 3-line shims over `output-es/`**: the webview entry
  CALLS `main()`, because importing the PS module alone runs nothing. The host entry
  RE-EXPORTS `activate` (`import { activate } from "../output-es/Host.Main/index.js";
  export { activate };`). Miss the call/re-export and you ship a dead bundle.
- **spago registry cache lives in the workspace**: the devcontainer sets
  `XDG_CACHE_HOME=/workspaces/vsc-ext-dev/.cache`, so the one-time registry
  clone persists across container rebuilds. A fresh clone needs GitHub access;
  once `.cache/spago-nodejs/` exists, spago tolerates refresh failures
  ("will proceed anyways" is non-fatal).
- **Never `npm install purescript` in the workspace**: the toolchain is
  pinned exactly (`purescript@0.15.16` in package.json, installed by
  `npm ci`). If the IDE offers to "install purs", decline; a stray install
  rewrites manifest+lock and spago rejects the old binary
  ("Unsupported PureScript version").
- **Rootless podman pollutes ownership**: verification runs like
  `podman run -v $PWD:/build … npm ci` create files owned by uid 101000
  (userns-mapped container root), which the `node` (uid 1000) devcontainer
  cannot delete, so `npm ci` then fails with EACCES. Clean up after container
  runs with `podman unshare rm -rf node_modules output output-es .spago dist media`.
- The message protocol lives in `packages/purs-graphs-protocol`:
  `scripts/smoke.cjs`, the webview, and the host all consume it; keep them in
  sync (the package's tests pin the wire bytes).
- **The `vscode` stub is a dev-only `file:` dep** creating
  `node_modules/vscode`: `spago test` resolves it for the headless
  binding/host tests. Never add a real `vscode` npm dependency, and never
  require the stub from shipped code; the host bundle must keep
  `external: ["vscode"]`.
- **`spago test` emits bare ESM**: FFI files must DEFAULT-import npm
  packages (`import vscode from "vscode"`); namespace imports don't surface
  CJS members under Node interop.
