// Test-only FFI for the Host.Main behavior suite: drives the dev-only vscode
// stub (node_modules/vscode) the same way scripts/capture-behavior.cjs does.
// Kept in test/ so the library surface ships zero test scaffolding. The
// default import is load-bearing — see src/Vscode/Version.js for why
// `import * as vscode` breaks under Node's native CJS-ESM interop.
import vscode from "vscode";

const { __stub } = vscode;

export const resetStub = () => vscode.__stub.reset();

export const makeContext = () => vscode.__stub.makeContext();

export const subscriptionsLength = (context) => () => context.subscriptions.length;

export const stubCommandIds = () => vscode.__stub.commands.map((entry) => entry.id);

export const invokeCommand = (id) => () => {
  const entry = vscode.__stub.commands.find((e) => e.id === id);
  if (entry) entry.handler();
};

// --- Documents / editors -------------------------------------------------

export const makeTextDocument = (spec) => () => vscode.__stub.textDocument(spec);

// `viewColumn` crosses erased (plain Int); a separate no-column factory yields
// `undefined`, the shape extension.ts:82 reads as "no column → Beside".
export const makeFakeEditor = (doc) => (viewColumn) => () => ({
  document: doc,
  viewColumn,
});

export const makeFakeEditorWithoutColumn = (doc) => () => ({
  document: doc,
  viewColumn: undefined,
});

export const setActiveTextEditor = (editor) => () => vscode.__stub.setActiveTextEditor(editor);

// --- Notifications ---------------------------------------------------------

export const drainErrorMessages = () => vscode.__stub.errorMessages.splice(0);

// --- Panels ----------------------------------------------------------------

export const panelsLength = () => vscode.__stub.panels.length;

export const panelAt = (index) => () => vscode.__stub.panels[index];

export const panelViewType = (panel) => () => panel.viewType;

export const panelTitle = (panel) => () => panel.title;

// The raw recorded showOptions: the PS `ViewColumn` newtype crossed the FFI
// erased to its Int (Beside = -2).
export const panelShowOptions = (panel) => () => panel.showOptions;

export const panelRevealsLength = (panel) => () => panel.reveals.length;

export const panelRevealAt = (panel) => (index) => () => panel.reveals[index];

// Nonce mask count ([A-Za-z0-9]{32}) — same regex as scripts/capture-behavior.cjs.
export const countNonceRuns = (panel) => () =>
  (panel.webview.html.match(/[A-Za-z0-9]{32}/g) || []).length;

export const webviewHtmlContains = (panel) => (needle) => () => panel.webview.html.includes(needle);

export const setPanelVisible = (panel) => (visible) => () => {
  panel.visible = visible;
};

export const fireDispose = (panel) => () => {
  for (const entry of [...vscode.__stub.disposeListeners]) {
    if (entry.panel === panel) entry.callback.call(entry.thisArg);
  }
};

// Reference identity — proves a re-preview created a NEW panel object.
export const panelReferenceEquals = (a) => (b) => a === b;

// --- Workspace / events ----------------------------------------------------

export const emitDocChange = (doc) => () => vscode.__stub.emitDocChange(doc);

export const setConfiguration = (section) => (key) => (value) => () =>
  vscode.__stub.setConfiguration(section, key, value);

// --- Webview messages ------------------------------------------------------

export const fireWebviewMessage = (panel) => (payload) => () => {
  for (const entry of [...vscode.__stub.messageListeners]) {
    if (entry.panel === panel) entry.callback.call(entry.thisArg, payload);
  }
};

// Raw webview→host payloads exactly as scripts/capture-behavior.cjs fires them
// (plain JS objects; the PS handler receives them AS argonaut Json).
export const errorPayload = { type: "error", kind: "dot", message: "bad dot" };

export const renderedPayload = { type: "rendered", kind: "dot", ms: 12 };

export const malformedPayload = { type: "xxx" };

// Interposes console.log for the duration of one synchronous action (the host
// logs renderer errors through console.log; Effect.Console.log calls into it).
export const captureLogs = (action) => () => {
  const lines = [];
  const original = console.log;
  console.log = (...args) => {
    lines.push(args.map((a) => (typeof a === "string" ? a : String(a))).join(" "));
  };
  try {
    action();
  } finally {
    console.log = original;
  }
  return lines;
};

// --- postMessage observations ----------------------------------------------

export const postMessagesLength = () => vscode.__stub.postMessages.length;

// Deep-equality via stringify: postMessage payloads are plain JS objects, so
// JSON.stringify is the faithful observation point (key order included).
export const postMessageStringifyAt = (index) => () =>
  JSON.stringify(vscode.__stub.postMessages[index]);
