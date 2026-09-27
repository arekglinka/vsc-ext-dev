// Host smoke test: end-to-end check of the SHIPPED host bundle
// (dist/extension.js — the PureScript Host.Main build) against the vendored
// `vscode` stub (node_modules/vscode → vendor/vscode-stub). Drives the surface
// the characterization fixtures froze: command registration, panel creation
// with CSP/HTML invariants, live-refresh update payloads, the dotEngine config
// override, the exact renderer-error log line, and panel dispose → recreate —
// plus the showcase gallery: panel + payload, reveal path, and the
// openSample → untitled-document hop.
//
// Usage:
//   node scripts/host-smoke.cjs
//   FAILPROBE=1 node scripts/host-smoke.cjs   (negative control — must FAIL)
//
// FAILPROBE intentionally corrupts one expected value so the script exits 1
// with a visible expected/actual diff — proving this harness can fail.
//
// Exit 0 = all steps PASS; exit 1 = first failure with a clear message.

const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const bundlePath = path.join(ROOT, "dist", "extension.js");

if (!fs.existsSync(bundlePath)) {
  console.error(`HOST SMOKE ABORT — host bundle not found: ${bundlePath}`);
  console.error("Build it first with `node esbuild.mjs` (or `npm run compile`).");
  process.exit(1);
}

// Load the stub first so the bundle's require("vscode") binds to the same
// module instance (same resolved path → same require cache entry).
const vscode = require("vscode");
const { __stub } = vscode;
const host = require(bundlePath); // AFTER reset-scheduling; state reset in main

const FAILPROBE = Boolean(process.env.FAILPROBE);

let step = 0;
function pass(name) {
  step += 1;
  console.log(`PASS  ${step}. ${name}`);
}
function fail(name, detail) {
  console.error(`FAIL  ${name}`);
  if (detail) console.error(detail);
  process.exit(1);
}
function assert(name, condition, detail) {
  if (!condition) fail(name, detail);
}
function assertJsonEq(name, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) fail(name, `  expected: ${e}\n  actual:   ${a}`);
}

// Drive the per-panel webview message listener (stub records one entry per panel).
function fireWebviewMessage(panel, payload) {
  for (const entry of [...__stub.messageListeners]) {
    if (entry.panel === panel) entry.callback(payload);
  }
}

function fireDispose(panel) {
  for (const entry of [...__stub.disposeListeners]) {
    if (entry.panel === panel) entry.callback();
  }
}

// Temporarily intercept console.log (the host logs renderer errors through it),
// restore immediately after, return the captured lines.
function captureConsoleLog(fn) {
  const lines = [];
  const original = console.log;
  console.log = (...args) => {
    lines.push(args.map((a) => (typeof a === "string" ? a : String(a))).join(" "));
  };
  try {
    fn();
  } finally {
    console.log = original;
  }
  return lines;
}

// Frozen wire shape (key order pinned by GraphProtocol.encodeHostUpdate).
const UPDATE_DOT = {
  type: "update",
  kind: "dot",
  source: "digraph{a->b}",
  fileName: "demo.dot",
  engine: "dot",
};
const UPDATE_NEATO = { ...UPDATE_DOT, engine: "neato" };

async function main() {
  __stub.reset();

  // -- Step 1: bundle exports activate --------------------------------------
  assert(
    "bundle exports activate",
    typeof host.activate === "function",
    `  typeof exports.activate = ${typeof host.activate}`
  );
  pass("dist/extension.js exports activate as a function");

  // -- Step 2: activate → exact command registration -------------------------
  const context = __stub.makeContext();
  host.activate(context);
  const ids = __stub.commands.map((c) => c.id);
  assertJsonEq("registered command ids", ids, [
    "pursGraphs.previewDot",
    "pursGraphs.previewGraph",
    "pursGraphs.showcase",
    "pursGraphs.fluentPanel",
  ]);
  pass("activate registers the two preview commands plus showcase and fluent panel");

  const previewDot = __stub.commands.find((c) => c.id === "pursGraphs.previewDot").handler;

  // -- Step 3: preview a .dot doc → panel + CSP/HTML invariants ---------------
  const demoDoc = __stub.textDocument({
    fileName: "demo.dot",
    languageId: "dot",
    text: "digraph{a->b}",
  });
  __stub.setActiveTextEditor({ document: demoDoc, viewColumn: 1 });
  const pm = __stub.postMessages;
  await previewDot();
  const panel = __stub.panels[0];
  assert("panel created", Boolean(panel), `  panels.length = ${__stub.panels.length}`);
  assert(
    "panel title",
    panel.title === "Preview: demo.dot",
    `  title = ${JSON.stringify(panel.title)}`
  );
  const html = panel.webview.html;
  assert(
    "CSP allows wasm-unsafe-eval",
    html.includes("'wasm-unsafe-eval'"),
    "  html is missing 'wasm-unsafe-eval'"
  );
  assert("CSP nonce present", html.includes("nonce-"), "  html is missing nonce-");
  assert(
    "CSP img-src vscode-webview:",
    html.includes("img-src vscode-webview:"),
    "  html is missing img-src vscode-webview:"
  );
  pass(`panel created: ${panel.title} (CSP + nonce present)`);

  // -- Step 4: live refresh payloads (default engine, then neato) -------------
  let postsBefore = pm.length;
  __stub.emitDocChange(demoDoc);
  // Negative control: FAILPROBE=1 corrupts this expectation → visible diff, exit 1.
  const expectedInitial = FAILPROBE ? { ...UPDATE_DOT, engine: "failprobe-corrupted" } : UPDATE_DOT;
  assertJsonEq("live-refresh payload (engine dot)", pm[postsBefore], expectedInitial);
  __stub.setConfiguration("pursGraphs", "dotEngine", "neato");
  postsBefore = pm.length;
  __stub.emitDocChange(demoDoc);
  assertJsonEq("live-refresh payload (engine neato)", pm[postsBefore], UPDATE_NEATO);
  __stub.setConfiguration("pursGraphs", "dotEngine", "dot"); // restore default
  pass("doc change posts exact update payloads (engine dot → neato via config)");

  // -- Step 5: webview error message → exact console line ----------------------
  const errorLogs = captureConsoleLog(() =>
    fireWebviewMessage(panel, { type: "error", kind: "dot", message: "bad dot" })
  );
  assert(
    "error log line exact",
    errorLogs.length === 1 && errorLogs[0] === "[purs-graphs] dot render error: bad dot",
    `  captured: ${JSON.stringify(errorLogs)}`
  );
  pass('webview error logs "[purs-graphs] dot render error: bad dot"');

  // -- Step 6: panel dispose → registry cleared → doc change → new panel -------
  fireDispose(panel);
  __stub.emitDocChange(demoDoc); // leaked per-panel listener still fires; no new panel from this
  await previewDot();
  assert(
    "new panel after dispose",
    __stub.panels.length === 2 && __stub.panels[1] !== panel,
    `  panels.length = ${__stub.panels.length}`
  );
  pass("dispose clears the registry: next preview creates a NEW panel");

  // -- Step 7: showcase gallery ------------------------------------------------
  const showcase = __stub.commands.find((c) => c.id === "pursGraphs.showcase").handler;
  const postsBeforeShowcase = pm.length;
  await showcase();
  const galleryPanel = __stub.panels[2];
  assert(
    "showcase panel created",
    Boolean(galleryPanel) && galleryPanel.viewType === "pursGraphs.showcase",
    `  panels.length = ${__stub.panels.length}`
  );
  assert(
    "showcase title",
    galleryPanel.title === "Purs Graphs Showcase",
    `  title = ${JSON.stringify(galleryPanel.title)}`
  );
  const galleryHtml = galleryPanel.webview.html;
  assert(
    "gallery CSP keeps wasm-unsafe-eval + nonce",
    galleryHtml.includes("'wasm-unsafe-eval'") && galleryHtml.includes("nonce-"),
    "  gallery html is missing CSP invariants"
  );
  assert(
    "gallery nav + open-editor anchors present",
    galleryHtml.includes('id="nav"') && galleryHtml.includes('id="open-editor"'),
    "  gallery html is missing DOM anchors"
  );
  assert(
    "gallery script tag carries the nonce exactly (no literal backslashes)",
    /<script nonce='[^'\\]/.test(galleryHtml) && !galleryHtml.includes('nonce=\\"'),
    "  gallery script nonce attribute is malformed (CSP would block the webview)"
  );
  const showcaseMsg = pm[postsBeforeShowcase];
  assert(
    "showcase payload posted",
    Boolean(showcaseMsg) && showcaseMsg.type === "showcase" && Array.isArray(showcaseMsg.samples),
    `  posted = ${JSON.stringify(showcaseMsg?.type)}`
  );
  assertJsonEq("showcase post total", pm.length, postsBeforeShowcase + 1);
  assertJsonEq("showcase sample count", showcaseMsg.samples.length, 6);
  assertJsonEq(
    "showcase kinds",
    showcaseMsg.samples.map((s) => s.kind),
    ["dot", "dot", "dot", "dot", "graph", "graph"]
  );
  pass("showcase panel + payload (6 samples, dot & graph kinds)");

  await showcase(); // reveal path
  assert(
    "second showcase re-reveals the SAME panel",
    __stub.panels.length === 3 && pm.length === postsBeforeShowcase + 2,
    `  panels.length = ${__stub.panels.length}, posts = ${pm.length}`
  );
  pass("second showcase reveals the existing panel and re-posts the payload");

  fireWebviewMessage(galleryPanel, { type: "openSample", id: "ci-pipeline" });
  const opened = __stub.openedDocuments[0];
  assert(
    "openSample opens an untitled dot doc",
    Boolean(opened) && opened.languageId === "dot" && opened.getText().includes("ci_pipeline"),
    `  opened = ${JSON.stringify(opened && { languageId: opened.languageId, text: opened.getText().slice(0, 20) })}`
  );
  assert("opened doc shown", __stub.shownDocuments.length === 1);
  pass("openSample → untitled doc (language dot) opened and shown");

  // -- Step 8: fluent panel (Rust/WASM force animation) -------------------------
  const fluent = __stub.commands.find((c) => c.id === "pursGraphs.fluentPanel").handler;
  const postsBeforeFluent = pm.length;
  await fluent();
  const fluentPanel = __stub.panels[3];
  assert(
    "fluent panel created",
    Boolean(fluentPanel) && fluentPanel.viewType === "pursGraphs.fluent",
    `  panels.length = ${__stub.panels.length}`
  );
  assert(
    "fluent title",
    fluentPanel.title === "Purs Graphs Fluent Panel",
    `  title = ${JSON.stringify(fluentPanel.title)}`
  );
  const fluentHtml = fluentPanel.webview.html;
  assert(
    "fluent CSP keeps wasm-unsafe-eval + nonce",
    fluentHtml.includes("'wasm-unsafe-eval'") && fluentHtml.includes("nonce-"),
    "  fluent html is missing CSP invariants"
  );
  assert(
    "fluent canvas + status anchors present",
    fluentHtml.includes('id="canvas"') &&
      fluentHtml.includes('id="status"') &&
      fluentHtml.includes('id="desc"'),
    "  fluent html is missing DOM anchors"
  );
  assert(
    "fluent script tag carries the nonce exactly (no literal backslashes)",
    /<script nonce='[^'\\]/.test(fluentHtml) && !fluentHtml.includes('nonce=\\"'),
    "  fluent script nonce attribute is malformed (CSP would block the webview)"
  );
  const fluentMsg = pm[postsBeforeFluent];
  assert(
    "fluent payload posted",
    Boolean(fluentMsg) &&
      fluentMsg.type === "fluentPanel" &&
      Array.isArray(fluentMsg.nodes) &&
      Array.isArray(fluentMsg.edges) &&
      fluentMsg.nodes.length > 0 &&
      fluentMsg.edges.length > 0,
    `  posted = ${JSON.stringify(fluentMsg?.type)}`
  );
  assertJsonEq("fluent post total", pm.length, postsBeforeFluent + 1);
  pass("fluent panel + payload (Rust/WASM force simulation)");

  await fluent(); // reveal path
  assert(
    "second fluent re-reveals the SAME panel",
    __stub.panels.length === 4 && pm.length === postsBeforeFluent + 2,
    `  panels.length = ${__stub.panels.length}, posts = ${pm.length}`
  );
  pass("second fluent reveal re-posts the payload");

  fireWebviewMessage(fluentPanel, { type: "ready" });
  assert(
    "ready from the webview re-pushes the payload (load race fix)",
    pm.length === postsBeforeFluent + 3 && pm[pm.length - 1].type === "fluentPanel",
    `  posts = ${pm.length}, last = ${JSON.stringify(pm[pm.length - 1]?.type)}`
  );
  pass("ready message re-pushes the fluent payload");
}

const timeout = setTimeout(() => {
  console.error("HOST SMOKE TIMEOUT — bundle did not finish within 15s");
  process.exit(1);
}, 15000);

main()
  .then(() => {
    clearTimeout(timeout);
    console.log(`HOST SMOKE OK — ${step} steps passed`);
    process.exit(0);
  })
  .catch((err) => {
    console.error("HOST SMOKE FAILED —", err?.stack ?? err);
    process.exit(1);
  });
