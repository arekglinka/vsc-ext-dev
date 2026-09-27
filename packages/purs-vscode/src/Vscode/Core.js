// vscode resolves to the dev-only stub in node_modules. The default import is
// load-bearing: under Node's native CJS-ESM interop, `import * as vscode` does
// not surface `__stub` (or `ViewColumn`) on the namespace — only the default
// export is the full `module.exports`.
import vscode from "vscode";

export const pushSubscription = (context) => (disposable) => () => {
  context.subscriptions.push(disposable);
};

export const dispose = (disposable) => () => {
  disposable.dispose();
};

export const extensionUri = (context) => () => context.extensionUri;

export const joinPath = (base) => (segments) => () => vscode.Uri.joinPath(base, ...segments);

export const uriToString = (uri) => () => uri.toString();
