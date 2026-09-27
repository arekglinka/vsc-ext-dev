// vscode resolves to the dev-only stub in node_modules. The default import is
// load-bearing: under Node's native CJS-ESM interop, `import * as vscode` does
// not surface `__stub` (or `ViewColumn`) on the namespace — only the default
// export is the full `module.exports`.
import vscode from "vscode";

export const panelReveal = (panel) => (column) => () => panel.reveal(column);

export const panelVisible = (panel) => () => panel.visible;

// A nullary `Effect Unit` PS handler IS the JS thunk `() => …` — call it.
export const panelOnDispose = (panel) => (handler) => () => panel.onDidDispose(() => handler());

export const webviewOf = (panel) => () => panel.webview;

export const setWebviewHtml = (webview) => (html) => () => {
  webview.html = html;
};

// Fire-and-forget: the Thenable is discarded — no `.catch`, no Aff wrapper
// (parity with `void panel.webview.postMessage(msg)` at extension.ts:142).
// The argonaut `Json` IS the raw JS value and passes through untouched.
export const postMessage = (webview) => (message) => () => {
  webview.postMessage(message);
};

export const asWebviewUri = (webview) => (uri) => () => webview.asWebviewUri(uri);

// The payload handler is `(Json -> Effect Unit)` — a JS function returning a
// thunk; wrap as `(data) => handler(data)()`. The raw JS payload (webview
// `postMessage` data) arrives AS argonaut Json, no re-serialization.
export const onDidReceiveMessage = (webview) => (handler) => () =>
  webview.onDidReceiveMessage((data) => handler(data)());
