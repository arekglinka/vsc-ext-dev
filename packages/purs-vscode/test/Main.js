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
