// vscode resolves to the dev-only stub in node_modules. The default import is
// load-bearing: under Node's native CJS-ESM interop, `import * as vscode` does
// not surface `__stub` (or `ViewColumn`) on the namespace — only the default
// export is the full `module.exports`.
import vscode from "vscode";

export const getConfiguration = (section) => () => vscode.workspace.getConfiguration(section);

export const getConfigString = (config) => (key) => (defaultValue) => () =>
  config.get(key, defaultValue);

// An `Effect Unit` PS handler is the JS thunk `() => …`; the callback wraps it
// as `(event) => handler(event)()` — invoke the returned thunk.
export const onDidChangeTextDocument = (handler) => () =>
  vscode.workspace.onDidChangeTextDocument((event) => handler(event)());

export const eventDocument = (event) => () => event.document;

// Untitled-document creation (showcase gallery). The options object carries
// exactly the field names the vscode API expects; the stub resolves
// synchronously (see the .purs header note on the Thenable convention).
export const openTextDocumentWithContent = (language) => (content) => () =>
  vscode.workspace.openTextDocument({ language, content });
