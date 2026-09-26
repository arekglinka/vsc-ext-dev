# AGENTS.md

## Project

`vsc-ext-dev` is the standalone repo for the **Purs Graphs** VSCode extension:
live previews of Graphviz DOT files and JSON graph specs. The webview is
PureScript — FFI bindings to `dagre` (layout) and `@viz-js/viz` (Graphviz WASM)
are vendored under `packages/`.

## Stack

- PureScript 0.15.16, spago 1.x workspace (registry 61.0.0), purs-backend-es
- TypeScript extension host (vscode ^1.85), esbuild bundling (host CJS, webview IIFE)
- `node:22-slim` devcontainer — single `devcontainer.json`, toolchain via `npm ci`

## Build Commands

| Command | Purpose |
|---|---|
| `npm run build` | `spago build` — compile vendored libs + webview package |
| `npm run backend` | `purs-backend-es build` — `output/` corefn → `output-es/` ES modules |
| `npm run typecheck` | `tsc --noEmit` on the TS host |
| `node esbuild.mjs` | Build `dist/extension.js` + `media/webview.js` |
| `npm run compile` | All of the above in order |
| `npm test` | Library tests + headless webview smoke test (`scripts/smoke.cjs`) |
| `npm run package` | compile + `vsce package` → `purs-graphs.vsix` |
| `npm run format:check` | purs-tidy + biome gate |

## Code Style

- PureScript: 2-space, 100-col, purs-tidy. FFI: thin JS, logic in PureScript,
  `Effect`-returning thunks, no exceptions across the boundary.
- TS/JS: biome, 2-space, double quotes, semicolons.
- Never suppress type errors; no `unsafeCoerce`.

## Gotchas

- **spago needs git in PATH** (even via npx) — that's why the devcontainer
  pulls the git feature.
- **Two output dirs**: `spago build` → `output/` (corefn); `purs-backend-es` →
  `output-es/`. The webview bundle imports from `output-es/Webview.Main/index.js`.
- **esbuild.mjs tolerates missing output-es** (host bundle still builds) but
  `npm run compile` always runs the backend first.
- **viz.js WASM is inlined** in the npm package — no `.wasm` loader config in
  esbuild; the webview CSP needs `'wasm-unsafe-eval'` (see `src/extension.ts`).
- **`entry.js` must call `main()`** — importing the PS module alone doesn't run it.
- **spago registry cache lives in the workspace**: the devcontainer sets
  `XDG_CACHE_HOME=/workspaces/vsc-ext-dev/.cache`, so the one-time registry
  clone persists across container rebuilds. A fresh clone needs GitHub access;
  once `.cache/spago-nodejs/` exists, spago tolerates refresh failures
  ("will proceed anyways" is non-fatal).
- **Never `npm install purescript` in the workspace** — the toolchain is
  pinned exactly (`purescript@0.15.16` in package.json, installed by
  `npm ci`). If the IDE offers to "install purs", decline; a stray install
  rewrites manifest+lock and spago rejects the old binary
  ("Unsupported PureScript version").
- **Rootless podman pollutes ownership**: verification runs like
  `podman run -v $PWD:/build … npm ci` create files owned by uid 101000
  (userns-mapped container root), which the `node` (uid 1000) devcontainer
  cannot delete — `npm ci` then fails with EACCES. Clean up after container
  runs with `podman unshare rm -rf node_modules output output-es .spago dist media`.
- The host message protocol in `src/extension.ts` is the contract — keep
  `Webview.Main` in sync when changing it.
