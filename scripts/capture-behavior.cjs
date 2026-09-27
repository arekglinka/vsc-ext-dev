// Characterization capture for the extension host: loads the CURRENT host
// bundle (default dist/extension.js, built from src/extension.ts) against the
// vendored `vscode` stub (node_modules/vscode → vendor/vscode-stub), drives
// every behavioral branch, and freezes all observations into a JSON fixture.
//
// The fixture is the FROZEN parity oracle — Task 11 re-runs this script
// against the PureScript host bundle and diffs the two JSON files. Exit 0
// means every step executed; there are NO pass/fail assertions on recorded
// values here (the fixture itself is the oracle).
//
// Usage:
//   node scripts/capture-behavior.cjs [--out <path>]
//   HOST_BUNDLE=<path> node scripts/capture-behavior.cjs [--out <path>]
//
// Deterministic by construction: no timestamps, the random nonce is masked
// as <NONCE>, everything else is a pure function of the host bundle + stub.

const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");

function flagValue(flag) {
  const i = process.argv.indexOf(flag);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : undefined;
}

const bundleArg = process.env.HOST_BUNDLE || "dist/extension.js";
const outArg = flagValue("--out") || "scripts/fixtures/characterization.json";
const bundlePath = path.resolve(ROOT, bundleArg);
const outPath = path.resolve(ROOT, outArg);

if (!fs.existsSync(bundlePath)) {
  console.error(`CAPTURE ABORT — host bundle not found: ${bundlePath}`);
  console.error("Build it first with `node esbuild.mjs`, or point HOST_BUNDLE at another bundle.");
  process.exit(1);
}

// Load the stub first so the bundle's require("vscode") binds to the same
// module instance (same resolved path → same require cache entry).
const vscode = require("vscode");
const { __stub } = vscode;

// The nonce is exactly 32 alphanumeric chars (extension.ts getNonce); nothing
// else in the HTML template produces a run that long.
const NONCE_RE = /[A-Za-z0-9]{32}/g;
const maskNonces = (html) => html.replace(NONCE_RE, "<NONCE>");

// Drain helpers: take everything recorded since the last drain, so each step
// records exactly its own observations.
const drainErrors = () => __stub.errorMessages.splice(0);

function fireWebviewMessage(payload) {
  for (const entry of [...__stub.messageListeners]) {
    entry.callback(payload);
  }
}

function fireDispose(panel) {
  for (const entry of [...__stub.disposeListeners]) {
    if (entry.panel === panel) entry.callback();
  }
}

// Temporarily intercept console.log (the host logs renderer errors through
// it), restore immediately after, return the captured lines.
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

async function main() {
  __stub.reset();
  const host = require(bundlePath); // AFTER reset — records only this run

  const fixture = {};
  const pm = __stub.postMessages;

  // -- Step 1: activate → command registration -----------------------------
  const context = __stub.makeContext();
  host.activate(context);
  fixture.commands = {
    ids: __stub.commands.map((c) => c.id),
    contextSubscriptionCount: context.subscriptions.length,
  };
  const previewDot = __stub.commands.find((c) => c.id === "pursGraphs.previewDot").handler;
  const previewGraph = __stub.commands.find((c) => c.id === "pursGraphs.previewGraph").handler;

  // -- Step 2: command with NO active editor --------------------------------
  __stub.setActiveTextEditor(undefined);
  await previewDot();
  fixture.noEditorError = { previewDot: drainErrors() };
  await previewGraph();
  fixture.noEditorError.previewGraph = drainErrors();

  // -- Step 3: wrong-kind active editor -------------------------------------
  const demoDoc = __stub.textDocument({
    fileName: "demo.dot",
    languageId: "dot",
    text: "digraph{a->b}",
  });
  const readmeDoc = __stub.textDocument({
    fileName: "README.md",
    languageId: "markdown",
    text: "# hello",
  });
  __stub.setActiveTextEditor({ document: readmeDoc, viewColumn: 1 });
  await previewDot(); // dot command against a markdown doc
  fixture.wrongKindError = { previewDotAgainstReadme: drainErrors() };
  __stub.setActiveTextEditor({ document: demoDoc, viewColumn: 1 });
  await previewGraph(); // graph command against a dot doc
  fixture.wrongKindError.previewGraphAgainstDot = drainErrors();

  // -- Step 4: preview the .dot doc → panel creation + html -----------------
  __stub.setActiveTextEditor({ document: demoDoc, viewColumn: 1 });
  await previewDot();
  const panel = __stub.panels[0];
  const html = panel.webview.html;
  fixture.panel = {
    viewType: panel.viewType,
    title: panel.title,
    showOptions: panel.showOptions,
    options: {
      enableScripts: panel.options.enableScripts,
      localResourceRoots: panel.options.localResourceRoots.map((u) => u.toString()),
    },
    html: maskNonces(html),
    nonceMaskedCount: (html.match(NONCE_RE) || []).length,
    csp: {
      hasWasmUnsafeEval: html.includes("'wasm-unsafe-eval'"),
      hasImgSrcWebview: html.includes("img-src vscode-webview:"),
    },
  };
  fixture.reveal = { firstPreview: panel.reveals[0] };
  fixture.postMessages = { initialPreview: pm.slice(0) };

  // -- Step 5: second preview of the SAME doc → reveal, no new panel --------
  await previewDot();
  fixture.reveal.secondPreview = panel.reveals[1];
  fixture.reveal.panelsCountAfterSecondPreview = __stub.panels.length;
  fixture.postMessages.secondPreview = pm.slice(1);

  // -- Step 6: live refresh while panel visible ------------------------------
  __stub.emitDocChange(demoDoc);
  fixture.postMessages.liveRefreshVisible = pm.slice(2);

  // -- Step 7: live refresh suppressed while panel hidden --------------------
  panel.visible = false;
  const postsBeforeHidden = pm.length;
  __stub.emitDocChange(demoDoc);
  fixture.postMessages.liveRefreshWhileHidden = {
    postsBefore: postsBeforeHidden,
    postsAfter: pm.length,
    newPosts: pm.slice(postsBeforeHidden),
  };

  // -- Step 8: pursGraphs.dotEngine config override --------------------------
  panel.visible = true;
  __stub.setConfiguration("pursGraphs", "dotEngine", "neato");
  __stub.emitDocChange(demoDoc);
  fixture.postMessages.engineNeato = pm.slice(postsBeforeHidden);
  __stub.setConfiguration("pursGraphs", "dotEngine", "dot"); // back to default for remaining steps

  // -- Step 9: webview error message → exact console line --------------------
  const errorLogs = captureConsoleLog(() =>
    fireWebviewMessage({ type: "error", kind: "dot", message: "bad dot" })
  );

  // -- Step 10: rendered + malformed messages → silent -----------------------
  const benignLogs = captureConsoleLog(() => {
    fireWebviewMessage({ type: "rendered", kind: "dot", ms: 12 });
    fireWebviewMessage({ type: "xxx" });
  });
  fixture.consoleLogs = { error: errorLogs, renderedAndMalformed: benignLogs };

  // -- Step 11: panel dispose → map removal proof → recreate -----------------
  const panelsCountBefore = __stub.panels.length;
  fireDispose(panel);
  const postsBeforeDisposeEmit = pm.length;
  __stub.emitDocChange(demoDoc);
  const panelsCountAfterDisposeEmit = __stub.panels.length;
  const postToDisposedPanel = pm.slice(postsBeforeDisposeEmit);
  await previewDot(); // same doc: map was cleared → a NEW panel is created
  const newPanel = __stub.panels[__stub.panels.length - 1];
  fixture.disposeRecreate = {
    panelsCountBefore,
    panelsCountAfterDisposeEmit,
    postToDisposedPanelAfterEmit: postToDisposedPanel,
    panelsCountAfterReopen: __stub.panels.length,
    reopenedPanelIsNewObject: newPanel !== panel,
    reopenedPanelReveals: newPanel.reveals,
    postAfterReopen: pm.slice(postsBeforeDisposeEmit + postToDisposedPanel.length),
  };

  // -- Step 12: .graph.json doc → kind "graph" -------------------------------
  const graphDoc = __stub.textDocument({
    fileName: "g.graph.json",
    languageId: "json",
    text: '{"nodes":[]}',
  });
  __stub.setActiveTextEditor({ document: graphDoc, viewColumn: 1 });
  await previewGraph();
  fixture.graphKind = pm[pm.length - 1];

  // -- Step 13: .gv extension + languageId fallback (kindForDocument order) --
  const gvDoc = __stub.textDocument({
    fileName: "notes.gv",
    languageId: "plaintext",
    text: "digraph{b->c}",
  });
  __stub.setActiveTextEditor({ document: gvDoc, viewColumn: 2 });
  await previewDot();
  fixture.gvKind = pm[pm.length - 1];

  const bareDoc = __stub.textDocument({
    fileName: "dotfile", // no extension — only languageId can classify it
    languageId: "dot",
    text: "digraph{d}",
  });
  __stub.setActiveTextEditor({ document: bareDoc, viewColumn: 1 });
  await previewDot();
  fixture.languageIdKind = pm[pm.length - 1];

  // Bonus branch (reveal fallback): viewColumn undefined → ViewColumn.Beside.
  __stub.setActiveTextEditor({ document: bareDoc, viewColumn: undefined });
  await previewDot();
  const barePanel = __stub.panels.find((p) => p.title === "Preview: dotfile");
  fixture.reveal.undefinedColumnPreview = barePanel.reveals;

  return fixture;
}

const REQUIRED_KEYS = [
  "commands",
  "noEditorError",
  "wrongKindError",
  "panel",
  "reveal",
  "postMessages",
  "consoleLogs",
  "disposeRecreate",
  "graphKind",
  "gvKind",
  "languageIdKind",
];

main()
  .then((fixture) => {
    const missing = REQUIRED_KEYS.filter((k) => !(k in fixture));
    if (missing.length > 0) {
      console.error(`CAPTURE INCOMPLETE — steps did not populate: ${missing.join(", ")}`);
      process.exit(1);
    }
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, `${JSON.stringify(fixture, null, 2)}\n`);
    console.log(
      `CAPTURE OK — ${REQUIRED_KEYS.length} step groups, ` +
        `${JSON.stringify(fixture).length} bytes → ${path.relative(ROOT, outPath)}`
    );
  })
  .catch((err) => {
    console.error("CAPTURE FAILED —", err?.stack ?? err);
    process.exit(1);
  });
