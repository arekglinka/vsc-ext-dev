# Multistage build for the Purs Graphs extension, driven by GitHub Actions.
# Stage boundaries double as cache boundaries: with buildx `type=gha` cache,
# a source change reuses the `deps` layer (no `npm ci` rerun); the final
# `artifact` stage is a scratch image containing exactly the VSIX.

FROM node:22-slim AS deps
# git: required by spago (registry resolution) and vsce packaging
RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /repo
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

FROM deps AS source
COPY . .

FROM source AS build
# spago registry cache inside the workspace participates in layer caching
ENV XDG_CACHE_HOME=/repo/.cache
RUN npm run build \
  && npm run backend \
  && node esbuild.mjs

FROM build AS test
RUN npm run format:check && npm test

# Rust engine: unit tests on the host target AND a release build for
# wasm32-unknown-unknown (the target the extension actually ships).
FROM rust:1-slim AS rust-tests
WORKDIR /crate
COPY fluent-wasm/ .
RUN rustup target add wasm32-unknown-unknown \
  && cargo test \
  && cargo build --release --target wasm32-unknown-unknown \
  && touch /rust-tests-passed

FROM test AS gate
COPY --from=rust-tests /rust-tests-passed /rust-tests-passed

FROM gate AS vsix
RUN mkdir -p /out \
  && npx @vscode/vsce package --no-dependencies -o /out/purs-graphs.vsix

FROM scratch AS artifact
COPY --from=vsix /out/purs-graphs.vsix /purs-graphs.vsix
