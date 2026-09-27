# AGENTS.md

Start here for repo mechanics; [README.md](README.md) is the human-facing
overview (features, architecture, CI, devcontainer access paths), and
[`fluent-wasm/README.md`](fluent-wasm/README.md) documents the Rust engine.

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
| `node esbuild.mjs` | Build `dist/extension.js` + `media/webview.js` (syncs foreign.js first) |
| `npm run compile` | `spago build` + purs-backend-es + esbuild bundles, no tsc |
| `npm test` | 6 spago suites (incl. webview Stage tests) + webview smoke + host smoke; needs `npm run compile` first on a clean tree (smokes load `media/webview.js`) |
| `npm run test:wasm` | Rust engine unit tests; falls back to musl + rust-lld when no C linker exists |
| `npm run wasm` | Rebuild the wasm artifact and regenerate the checked-in base64 module |
| `npm run package` | compile + `vsce package` → `purs-graphs.vsix` + auto-install into the devcontainer |
| `npm run install:extension` | refresh the installed extension from the current build (reload window after) |
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
- **foreign.js recopy**: purs-backend-es does NOT recopy foreign JS when only
  the `.js` changed; `esbuild.mjs` syncs `output/*/foreign.js` → `output-es/`
  before bundling. If you bundle by hand, run `npm run compile` instead.
- **Wasm reads must be Effect-ful**: `Webview.Fluent` reads node positions
  from mutable wasm linear memory; a pure signature lets purs-backend-es
  hoist the read out of the frame loop (symptom: nodes frozen at their
  frame-1 positions). Keep `engineX`/`engineY` in `Effect`.
- **Wasm artifact is checked in**: after editing `fluent-wasm/src/lib.rs`, run
  `npm run wasm` and commit the regenerated `fluent-wasm.js`. CI compiles
  both targets but does not regenerate the artifact.
- **Every new panel MUST handle `ready`**: VSCode drops messages posted
  before a webview finishes loading; each panel's message handler re-pushes
  its payload on `ready` (see `Host.Main`).
- **Triple-quoted PureScript strings cannot end with `"` and do not process
  escapes**: `"` inside `"""…"""` is a literal backslash. In HTML
  templates use single-quoted attributes (`nonce='…'`).
- **Installed extension ≠ workspace build**: the devcontainer's VSCode loads
  the extension from `~/.vscode-server/extensions/…`; `npm run package` /
  `install:extension` keep it in sync, plus a window reload. When a user
  reports "still broken", check which copy their window runs.

## CI

`.github/workflows/ci.yml` drives the multistage `Dockerfile` with
`docker/build-push-action` (`cache-from/to: type=gha, mode=max`) and exports
the VSIX from a scratch `artifact` target. Stage map and rationale live in
[README.md → CI](README.md#ci). The Rust stage runs engine unit tests AND a
`wasm32-unknown-unknown` release build.

`.github/workflows/devcontainer-image.yml` builds `Dockerfile.devcontainer`
(the dev environment definition) and publishes it to GHCR
(`…-devcontainer:master`) — treat that Dockerfile as the source of truth for
the environment; devcontainer.json builds it directly, features are gone.
