import * as vscode from "vscode";

/**
 * Wire protocol between the extension host and the PureScript webview.
 * Host -> webview: HostToWebview. Webview -> host: WebviewToHost.
 */

/** Message sent from the extension host to the webview. */
export interface HostToWebview {
  type: "update";
  kind: "dot" | "graph";
  source: string;
  fileName: string;
  /** Graphviz engine for dot previews (from pursGraphs.dotEngine setting). */
  engine: string;
}

/** Messages sent from the webview back to the extension host. */
export type WebviewToHost =
  | { type: "ready" }
  | { type: "rendered"; kind: "dot" | "graph"; ms: number }
  | { type: "error"; kind: "dot" | "graph"; message: string };

export function toWebviewToHost(data: unknown): WebviewToHost | undefined {
  if (typeof data !== "object" || data === null || !("type" in data)) {
    return undefined;
  }
  const msg = data as Record<string, unknown>;
  switch (msg.type) {
    case "ready":
      return { type: "ready" };
    case "rendered":
      if (msg.kind === "dot" || msg.kind === "graph") {
        return msg as unknown as WebviewToHost;
      }
      return undefined;
    case "error":
      if ((msg.kind === "dot" || msg.kind === "graph") && typeof msg.message === "string") {
        return msg as unknown as WebviewToHost;
      }
      return undefined;
    default:
      return undefined;
  }
}

const DOT_EXTNAMES = [".dot", ".gv"];

function kindForDocument(doc: vscode.TextDocument): "dot" | "graph" | undefined {
  if (DOT_EXTNAMES.includes(doc.fileName.slice(doc.fileName.lastIndexOf(".")).toLowerCase())) {
    return "dot";
  }
  if (doc.fileName.toLowerCase().endsWith(".graph.json")) {
    return "graph";
  }
  if (doc.languageId === "dot") {
    return "dot";
  }
  return undefined;
}

export function activate(context: vscode.ExtensionContext): void {
  const panels = new Map<string, vscode.WebviewPanel>();

  async function openPreview(kind: "dot" | "graph"): Promise<void> {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      vscode.window.showErrorMessage("Purs Graphs: open a .dot/.gv or *.graph.json file first.");
      return;
    }
    const actualKind = kindForDocument(editor.document);
    if (actualKind !== kind) {
      vscode.window.showErrorMessage(
        `Purs Graphs: this command previews ${
          kind === "dot" ? "a .dot/.gv file" : "a *.graph.json file"
        } — the active editor does not look like one.`
      );
      return;
    }
    const doc = editor.document;
    const panel = panels.get(doc.uri.toString()) ?? createPanel(doc, actualKind);
    panel.reveal(editor.viewColumn ? editor.viewColumn + 1 : vscode.ViewColumn.Beside);
    pushUpdate(panel, doc);
  }

  function createPanel(doc: vscode.TextDocument, kind: "dot" | "graph"): vscode.WebviewPanel {
    const panel = vscode.window.createWebviewPanel(
      "pursGraphs.preview",
      `Preview: ${doc.fileName.split("/").pop()}`,
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, "media")],
      }
    );
    panel.webview.html = getHtml(panel.webview, context.extensionUri);
    panels.set(doc.uri.toString(), panel);

    panel.webview.onDidReceiveMessage(
      (data: unknown) => {
        const msg = toWebviewToHost(data);
        if (!msg) {
          return;
        }
        if (msg.type === "error") {
          // Renderer errors are surfaced inside the webview itself; only log here.
          console.log(`[purs-graphs] ${msg.kind} render error: ${msg.message}`);
        }
      },
      undefined,
      context.subscriptions
    );

    panel.onDidDispose(() => panels.delete(doc.uri.toString()), undefined, context.subscriptions);

    // Live-refresh: re-send the source whenever the document changes.
    const onChange = vscode.workspace.onDidChangeTextDocument((event) => {
      if (event.document.uri.toString() === doc.uri.toString() && !panel.visible) {
        return;
      }
      if (event.document.uri.toString() === doc.uri.toString()) {
        pushUpdate(panel, event.document);
      }
    });
    context.subscriptions.push(onChange);

    return panel;
  }

  function pushUpdate(panel: vscode.WebviewPanel, doc: vscode.TextDocument): void {
    const kind = kindForDocument(doc);
    if (!kind) {
      return;
    }
    const msg: HostToWebview = {
      type: "update",
      kind,
      source: doc.getText(),
      fileName: doc.fileName.split("/").pop() ?? doc.fileName,
      engine: vscode.workspace.getConfiguration("pursGraphs").get<string>("dotEngine", "dot"),
    };
    void panel.webview.postMessage(msg);
  }

  context.subscriptions.push(
    vscode.commands.registerCommand("pursGraphs.previewDot", () => openPreview("dot")),
    vscode.commands.registerCommand("pursGraphs.previewGraph", () => openPreview("graph"))
  );
}

export function deactivate(): void {
  // Panels are disposed via their own onDidDispose handlers.
}

function getHtml(webview: vscode.Webview, extensionUri: vscode.Uri): string {
  const scriptUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, "media", "webview.js"));
  const nonce = getNonce();
  return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="
    default-src 'none';
    img-src vscode-webview: data:;
    style-src vscode-webview: 'unsafe-inline';
    script-src 'nonce-${nonce}' 'wasm-unsafe-eval';
    font-src vscode-webview:;">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Purs Graphs Preview</title>
  <style>
    body {
      margin: 0;
      padding: 12px;
      font-family: var(--vscode-font-family);
      color: var(--vscode-editor-foreground);
      background: var(--vscode-editor-background);
    }
    #status {
      font-size: 11px;
      opacity: 0.7;
      min-height: 1.2em;
      margin-bottom: 8px;
    }
    #status.error { color: var(--vscode-errorForeground); opacity: 1; }
    #canvas svg { max-width: 100%; height: auto; }
    #canvas .pg-edge { stroke: var(--vscode-editor-foreground); opacity: 0.4; }
    #canvas .pg-node { fill: var(--vscode-editor-widget-background); stroke: var(--vscode-focusBorder); }
    #canvas .pg-label {
      fill: var(--vscode-editor-foreground);
      font-family: var(--vscode-font-family);
      font-size: 11px;
      text-anchor: middle;
      dominant-baseline: middle;
      pointer-events: none;
    }
  </style>
</head>
<body>
  <div id="status"></div>
  <div id="canvas"></div>
  <script nonce="${nonce}" src="${scriptUri}"></script>
</body>
</html>`;
}

function getNonce(): string {
  let text = "";
  const possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  for (let i = 0; i < 32; i++) {
    text += possible.charAt(Math.floor(Math.random() * possible.length));
  }
  return text;
}
