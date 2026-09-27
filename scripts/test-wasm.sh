#!/bin/sh
# When no C linker exists (node:22-slim devcontainer), fall back to the
# self-contained musl target rustup ships (rust-lld + bundled CRT).
set -eu
cd "$(dirname "$0")/.."
if command -v cc >/dev/null 2>&1; then
  exec cargo test --manifest-path fluent-wasm/Cargo.toml
fi
RUSTFLAGS="-C linker=rust-lld" exec cargo test \
  --manifest-path fluent-wasm/Cargo.toml \
  --target x86_64-unknown-linux-musl
