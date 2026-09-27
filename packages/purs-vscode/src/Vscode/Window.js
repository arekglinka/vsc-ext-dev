// vscode resolves to the dev-only stub in node_modules. The default import is
// load-bearing: under Node's native CJS-ESM interop, `import * as vscode` does
// not surface the stub's members — only the default export is the full
// `module.exports`. See Vscode.Core.js.
import vscode from "vscode";

export const _activeTextEditorImpl = () => vscode.window.activeTextEditor;

export const showErrorMessage = (message) => () => vscode.window.showErrorMessage(message);

// The PanelOptions record is passed through AS-IS: a PureScript record IS a
// plain JS object with exactly the field names the vscode API expects
// (enableScripts, localResourceRoots). No normalization here — ever.
export const createWebviewPanel = (viewType) => (title) => (showOptions) => (options) => () =>
  vscode.window.createWebviewPanel(viewType, title, showOptions, options);

export const editorDocument = (editor) => () => editor.document;

export const _editorViewColumnImpl = (editor) => () => editor.viewColumn;

export const documentFileName = (document) => () => document.fileName;

export const documentLanguageId = (document) => () => document.languageId;

export const documentUri = (document) => () => document.uri;

export const documentText = (document) => () => document.getText();
