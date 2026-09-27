// vscode resolves to the dev-only stub in node_modules. The default import is
// load-bearing: under Node's native CJS-ESM interop, `import * as vscode` does
// not surface the stub's members — only the default export is the full
// `module.exports`. See Vscode.Core.js.
import vscode from "vscode";

// A PureScript `Effect Unit` value is a nullary JS thunk, so it doubles as
// the vscode command handler directly — no wrapping layer.
export const registerCommand = (id) => (handler) => () =>
  vscode.commands.registerCommand(id, handler);
