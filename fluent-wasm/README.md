# fluent-wasm — Rust force-simulation engine

Zero-dependency Rust crate compiled to `wasm32-unknown-unknown` that powers
the **Purs Graphs Fluent Panel** (`pursGraphs.fluentPanel`). The PureScript
webview owns the DOM and the frame loop; this crate owns the physics.

## Model

Springs (Hooke, toward a rest length) + softened Coulomb repulsion + weak
centering + a pointer repulsion well + a deterministic sinusoidal "breeze"
drift, integrated with heavy velocity damping (`DAMP = 0.86`) so the system
settles smoothly instead of oscillating. All constants live at the top of
[`src/lib.rs`](src/lib.rs) — tweak and rerun `npm run wasm` to feel the
difference.

Drag interaction: `grab(i)` pins node `i` to the pointer (position follows
the mouse, velocity zeroed, clamped to the stage margins) until `release()`;
springs drag the rest of the graph along and pull it back afterwards.

## Exports (the whole wasm ABI)

| Export | Purpose |
|---|---|
| `configure(nodes, edges)` | place nodes on a circle, reset velocities; capacities clamp at `MAX_NODES`/`MAX_EDGES` |
| `set_edge(k, a, b)` | register spring `k` between node indices |
| `set_mouse(x, y, active)` | pointer position in stage coordinates; enables the repulsion well |
| `grab(i)` / `release()` | start/end a drag on node `i` |
| `step(dt)` | advance the simulation (dt clamped to 0.001–0.033 s) |
| `node_count()` | active node count |
| `px_ptr()` / `py_ptr()` | pointers to the live `f32` position arrays in linear memory |

State lives in a fixed-capacity static arena: the module never allocates and
the memory buffer never grows, so the JS side can read positions through
zero-copy `Float32Array` views built directly over `px_ptr()`/`py_ptr()`.

## Build & test

```bash
npm run wasm        # cargo build --release --target wasm32-unknown-unknown,
                    # then regenerate webview-src/src/Webview/fluent-wasm.js
                    # (the checked-in base64 the webview bundle inlines)
npm run test:wasm   # cargo test (musl + rust-lld fallback without a C linker)
```

The extension ships the **checked-in** base64 module — CI verifies the crate
compiles for both the host and wasm32 targets, but does not regenerate the
artifact. After changing `src/lib.rs`, always run `npm run wasm` and commit
the regenerated file together with the source change.

Unit tests live in `src/lib.rs` under `#[cfg(test)]` (serialized on a mutex —
the sim is one global). They cover placement/reset, capacity clamping,
settling, grab pinning + release spring-back, pointer repulsion, idle drift,
and live-memory pointer exposure.
