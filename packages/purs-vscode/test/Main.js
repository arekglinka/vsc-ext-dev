// Test-only FFI: drives the dev-only vscode stub (node_modules/vscode) directly.
// Kept out of src/ so the library surface ships zero test scaffolding. The
// default import is load-bearing — see src/Vscode/Version.js for why
// `import * as vscode` breaks under Node's native CJS-ESM interop.
import vscode from "vscode";

export const makeContext = () => vscode.__stub.makeContext();

export const subscriptionsLength = (context) => () => context.subscriptions.length;

export const makeFakeDisposable = () =>
  vscode.commands.registerCommand("Test.VscodeMain.fake", () => {});

export const stubCommandsLength = () => vscode.__stub.commands.length;

export const resetStub = () => vscode.__stub.reset();

// --- Window drivers ---

export const makeTextDocument = (spec) => () => vscode.__stub.textDocument(spec);

export const makeFakeEditor = (doc) => (viewColumn) => () => ({
  document: doc,
  viewColumn,
});

export const setActiveTextEditor = (editor) => () => vscode.__stub.setActiveTextEditor(editor);

export const errorMessagesLength = () => vscode.__stub.errorMessages.length;

export const errorMessageAt = (index) => () => vscode.__stub.errorMessages[index];

export const panelsLength = () => vscode.__stub.panels.length;

export const panelViewType = (panel) => () => panel.viewType;

export const panelTitle = (panel) => () => panel.title;

export const panelShowOptions = (panel) => () => panel.showOptions;

// Options fidelity: read the record the FFI passed through AS-IS — a PS record
// is a plain JS object, so `options.enableScripts` must be exactly what PS sent.
export const panelEnableScripts = (panel) => () => panel.options.enableScripts;

export const panelLocalResourceRootsLength = (panel) => () =>
  panel.options.localResourceRoots.length;

// --- Commands drivers ---

export const commandsFind = (id) => () => vscode.__stub.commands.some((entry) => entry.id === id);

export const invokeCommand = (id) => () => {
  const entry = vscode.__stub.commands.find((e) => e.id === id);
  if (entry) entry.handler();
};

// --- Workspace drivers ---

export const setConfiguration = (section) => (key) => (value) => () =>
  vscode.__stub.setConfiguration(section, key, value);

export const emitDocChange = (doc) => () => vscode.__stub.emitDocChange(doc);

export const docChangeListenersLength = () => vscode.__stub.docChangeListeners.length;

// --- WebviewPanel drivers ---

export const panelRevealsLength = (panel) => () => panel.reveals.length;

// `reveal` records the RAW column value: a PS `ViewColumn` newtype crosses the
// FFI erased to its Int, so the reader returns the plain number.
export const panelRevealAt = (panel) => (index) => () => panel.reveals[index];

export const setPanelVisible = (panel) => (visible) => () => {
  panel.visible = visible;
};

// Mirrors the stub's own emit style (iterate a copy, call with thisArg) for the
// dispose listeners keyed by panel.
export const fireDispose = (panel) => () => {
  for (const entry of [...vscode.__stub.disposeListeners]) {
    if (entry.panel === panel) entry.callback.call(entry.thisArg);
  }
};

export const disposeListenersLength = () => vscode.__stub.disposeListeners.length;

export const messageListenersLength = () => vscode.__stub.messageListeners.length;

// Delivers a raw JS payload to the webview-message listeners of one panel —
// the same shape a real webview's postMessage would arrive with.
export const fireWebviewMessage = (panel) => (payload) => () => {
  for (const entry of [...vscode.__stub.messageListeners]) {
    if (entry.panel === panel) entry.callback.call(entry.thisArg, payload);
  }
};

export const webviewHtml = (webview) => () => webview.html;

export const postMessagesLength = () => vscode.__stub.postMessages.length;

// Deep-equality via stringify: postMessage payloads are plain JS objects, so
// JSON.stringify is the faithful observation point (key order included).
export const postMessageStringifyAt = (index) => () =>
  JSON.stringify(vscode.__stub.postMessages[index]);

export const openedDocumentsLength = () => vscode.__stub.openedDocuments.length;

export const shownDocumentsLength = () => vscode.__stub.shownDocuments.length;
