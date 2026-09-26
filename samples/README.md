# Sample graphs

Files to view with the **Purs Graphs** extension.

| File | Previewer | Engine |
|---|---|---|
| `system-design.graph.json` | Graph (JSON) | dagre |
| `kafka-topics.graph.json` | Graph (JSON) | dagre |
| `ci-pipeline.dot` | DOT | Graphviz (`dot`) |
| `oauth-flow.dot` | DOT | Graphviz (`dot`) |

## How to view

1. Install the extension (VSIX from the CI `build-extension` job artifact, or
   `npm run package` in `extensions/purs-graphs/`).
2. Open any file above in the editor.
3. Run **Purs Graphs: Preview DOT** (`Ctrl+Shift+G`) or
   **Purs Graphs: Preview Graph (JSON)** from the command palette.
4. Edit the file — the preview refreshes as you type.

DOT files also render at https://dreampuf.github.io/GraphvizOnline or any
Graphviz tooling; `*.graph.json` files follow the spec in the
[extension README](../README.md#json-graph-spec).
