# vsc-ext-dev: Purs Graphs VSCode extension

Standalone development repo for the **Purs Graphs** VSCode extension: live
previews for two graph formats, rendered by PureScript bindings to graph
libraries. The extension host and the webview are both PureScript.

| Preview | File type | Engine |
|---|---|---|
| **DOT preview** | `.dot` / `.gv` | Graphviz (viz.js WASM) via [`packages/purs-viz`](packages/purs-viz/) |
| **Graph (JSON) preview** | `*.graph.json` | dagre layout via [`packages/purs-dagre`](packages/purs-dagre/) |
| **Fluent panel** | — (command) | Rust force simulation compiled to WASM, see [`fluent-wasm/`](fluent-wasm/) |
| **Showcase gallery** | — (command) | all of the above, six built-in samples |

## Usage

1. Open a `.dot` file → run **Purs Graphs: Preview DOT** (`Ctrl+Shift+G`).
2. Open a `*.graph.json` file → run **Purs Graphs: Preview Graph (JSON)**.
3. Run **Purs Graphs: Fluent Panel** — a live force-directed animation whose
   physics (springs, repulsion, pointer forces) runs in Rust compiled to
   WebAssembly. **Hover** to push nodes away, **press and drag a node** to
   pull the graph around; it settles with a gentle idle drift.
4. No file at hand? Run **Purs Graphs: Showcase Gallery** — a demo panel with
   six samples (clusters, a radial `circo` layout, JSON+dagre graphs) rendered
   by the same pipeline. Pick a sample, then hit **Open sample in editor** to
   drop its source into an untitled editor and keep tinkering (DOT samples
   live-preview immediately; save JSON ones as `*.graph.json` first).

The preview opens beside the editor and **live-refreshes** as you type.
Errors render inline in the webview. Sample files live in [`samples/`](samples/).

### JSON graph spec

```json
{
  "rankDir": "LR",
  "nodes": [
    { "id": "api", "label": "API", "width": 120, "height": 60 },
    { "id": "db", "label": "Postgres", "width": 140, "height": 60 }
  ],
  "edges": [
    { "from": "api", "to": "db", "label": "SQL" }
  ]
}
```

### Settings

| Setting | Default | Description |
|---|---|---|
| `pursGraphs.dotEngine` | `dot` | Graphviz engine (`dot`, `neato`, `fdp`, `circo`, `twopi`) |

## Architecture

```
vsc-ext-dev/
├── host-src/                 PS extension host: Host.Main (activate),
│                             Host.Html / GalleryHtml / FluentHtml (CSP/HTML
│                             templates), Samples (in-repo demo graphs)
├── webview-src/              PureScript webview package (Webview.Main entry,
│                             Webview.Stage pure layout logic, tests)
├── packages/purs-vscode/     FFI bindings over the VSCode API
├── packages/purs-graphs-protocol/  shared host↔webview message protocol
├── packages/purs-dagre/      vendored: FFI bindings to dagre (layout)
├── packages/purs-viz/        vendored: FFI bindings to @viz-js/viz (DOT → SVG WASM)
├── fluent-wasm/              Rust force-simulation engine (→ wasm32, inlined)
├── vendor/vscode-stub/       dev-only `vscode` module test double
├── samples/                  sample .dot + .graph.json files to preview
├── scripts/                  wasm build/install/test helpers + smoke harnesses
├── esbuild.mjs               dist/extension.js (host) + media/webview.js (webview)
├── Dockerfile                multistage CI build (deps→build→test→rust→vsix)
├── .github/workflows/ci.yml  GitHub Actions: cached docker build → VSIX artifact
└── .devcontainer/            one devcontainer.json on node:22-slim
```

The webview is fully self-contained: viz.js WASM is inlined in the bundle, and
the webview runs under a strict CSP (nonce + `wasm-unsafe-eval`). The
host↔webview message protocol lives in
[`packages/purs-graphs-protocol/src/GraphProtocol.purs`](packages/purs-graphs-protocol/src/GraphProtocol.purs),
the single source of truth both sides import:

- host → webview: `{ type: "update", kind: "dot" | "graph", source, fileName, engine }`
- host → webview (gallery): `{ type: "showcase", samples: [{ id, title, description, kind, source, fileName, engine }] }`
- host → webview (fluent): `{ type: "fluentPanel", nodes: [{ id, label }], edges: [{ from, to }] }`
- webview → host: `{ type: "ready" } | { type: "rendered", kind, ms } | { type: "error", kind, message } | { type: "openSample", id }`

Every panel re-pushes its payload when the webview reports `ready` — messages
posted before the webview finished loading are dropped by VSCode, so the
handshake is mandatory for every new panel type.

## Build

Requires Node 22+ and git (spago needs git in PATH). No global toolchain:
`npm ci` installs purs, spago, purs-backend-es, purs-tidy, esbuild, and the
VSIX packager locally.

```bash
npm ci
npm run compile   # spago build + ES output + esbuild bundles (no tsc)
npm test          # 6 spago packages + webview smoke + host smoke
npm run test:wasm # Rust engine unit tests (musl fallback when no cc)
npm run package   # → purs-graphs.vsix, auto-installed into the devcontainer
```

Install: VSCode → Extensions view → `…` → *Install from VSIX*. Inside the
devcontainer, `npm run package` (or `npm run install:extension`) also
refreshes the installed copy automatically — reload the window afterwards.

## Development

`vendor/vscode-stub` is a dev-only `file:` dependency. It provides a fake
`vscode` module so the bindings and host packages test headlessly under
`spago test`. Never require it from shipped code: the host bundle keeps
`vscode` external, so the real API is used at runtime.

Release checklist: before publishing, verify in real VSCode. Press **F5**
(*Run Purs Graphs extension*, the Extension Development Host), open a sample
`.dot` or `.graph.json` from `samples/`, edit it, and confirm the preview
live-refreshes.

## CI

GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs a
multistage Docker build ([`Dockerfile`](Dockerfile)) with buildx layer
caching (`type=gha`): `deps` (npm ci keyed on the lockfile) → `build`
(PureScript + esbuild) → `test` (format gate + full `npm test`) →
`rust-tests` (engine unit tests on the host target + a release build for
`wasm32-unknown-unknown`) → `vsix` (packaging) → a `scratch` `artifact`
stage exporting exactly the VSIX, uploaded as a workflow artifact. A
source-only change reuses the `deps` layer; a lockfile change is the only
thing that re-pulls dependencies.

The shipped wasm is the checked-in base64 module
(`webview-src/src/Webview/fluent-wasm.js`): after editing
`fluent-wasm/src/lib.rs`, run `npm run wasm` to regenerate it and commit the
result — CI verifies the crate compiles for both targets but does not
regenerate the artifact.

## DevContainer

Single `.devcontainer/devcontainer.json` building
[`Dockerfile.devcontainer`](Dockerfile.devcontainer) — the whole environment
baked into one image: Node 22, git, GitHub CLI, tmux, unzip, Bun, and the
Rust toolchain with the `wasm32-unknown-unknown` and musl targets.
`npm ci` on create provides the PureScript toolchain, and OmO
([omo.dev](https://omo.dev/)) is installed globally for agent runs. CI
publishes the same image to GHCR
(`ghcr.io/arekglinka/vsc-ext-dev-devcontainer:master`) — point
`devcontainer.json` at that `image:` for pull-fast starts on machines where
building is inconvenient.

The container is named `purs-graphs-dev` and keeps running after the VSCode
client disconnects (`shutdownAction: "none"`), so two access paths share one
container:

- **Agents (headless)**: `podman exec -it purs-graphs-dev bash -lc 'omo ...'`
  (exec starts in `/workspaces/vsc-ext-dev`, where OmO keeps its `.omo`
  project dir; `containerUser` is `node`, use `-u root` for package
  installs).
- **Inspect (VSCode)**: reconnect normally via "Reopen in Container", or attach
  to the running container ("Dev Containers: Attach to Running Container").

Headless start without VSCode: `npm run devcontainer:up` — builds, applies
lifecycle commands, and leaves the container running (wraps the
`@devcontainers/cli`, shimming podman when docker is absent).

Two one-time notes: changing devcontainer config applies only to a NEW
container (`podman rm -f purs-graphs-dev`, then start again), and OmO needs
`/login` inside its TUI once per container to store model credentials.

## License

MIT. See [LICENSE](LICENSE).
