-- | Webview HTML/CSP template for the **Purs Graphs Fluent Panel**
-- | (`pursGraphs.fluentPanel`) — a live force-directed animation whose
-- | physics runs in Rust compiled to WebAssembly (`fluent-wasm/`, inlined
-- | into the webview bundle by `scripts/build-wasm.mjs`). Same
-- | security-critical CSP shape as `Host.Html` / `Host.GalleryHtml`:
-- | nonce'd `script-src` + `'wasm-unsafe-eval'` (the WASM compile needs it),
-- | `vscode-webview:` resource allow-list, no runtime fetch.
-- |
-- | DOM anchors consumed by `Webview.Main`'s fluent mode:
-- |   * `#stage`  — the animated SVG (injected by the webview)
-- |   * `#status` — frame counter / error line
-- |   * `#desc`   — static hint line
module Host.FluentHtml
  ( getFluentHtml
  ) where

import Prelude

-- | Render the fluent-panel HTML. Arguments mirror `Host.Html.getHtml`:
-- | `scriptUri` — webview resource URI of `media/webview.js`; `nonce` —
-- | from `Host.Html.getNonce`.
getFluentHtml :: String -> String -> String
getFluentHtml scriptUri nonce =
  """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="
    default-src 'none';
    img-src vscode-webview: data:;
    style-src vscode-webview: 'unsafe-inline';
    script-src 'nonce-"""
    <> nonce
    <>
      """' 'wasm-unsafe-eval';
    font-src vscode-webview:;">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Purs Graphs Fluent Panel</title>
  <style>
    html, body { height: 100%; }
    body {
      margin: 0;
      font-family: var(--vscode-font-family);
      color: var(--vscode-editor-foreground);
      background: var(--vscode-editor-background);
    }
    .fl-header { padding: 12px 16px 8px; border-bottom: 1px solid var(--vscode-panel-border); }
    .fl-header h1 { font-size: 1.05em; font-weight: 600; margin: 0 0 4px; }
    #desc { margin: 0 0 6px; font-size: 12px; opacity: 0.8; }
    #status { font-size: 11px; opacity: 0.7; min-height: 1.2em; }
    #status.error { color: var(--vscode-errorForeground); opacity: 1; }
    #canvas { padding: 8px 16px; }
    #stage {
      display: block;
      width: 100%;
      max-width: 900px;
      margin: 0 auto;
      border-radius: 10px;
      background:
        radial-gradient(ellipse at 30% 20%, rgba(91, 141, 239, 0.08), transparent 60%),
        radial-gradient(ellipse at 75% 80%, rgba(58, 166, 117, 0.07), transparent 55%);
      border: 1px solid var(--vscode-panel-border);
    }
    .fluent-edge {
      stroke: var(--vscode-focusBorder);
      stroke-width: 1.5;
      stroke-dasharray: 7 7;
      opacity: 0.55;
      animation: fl-dash 1.1s linear infinite;
    }
    .fluent-node {
      fill: var(--vscode-button-background);
      stroke: var(--vscode-button-foreground);
      stroke-width: 1;
      filter: drop-shadow(0 0 7px var(--vscode-focusBorder));
      transition: r 0.15s ease;
    }
    .fluent-node-g:hover .fluent-node { r: 20; }
    .fluent-label {
      fill: var(--vscode-editor-foreground);
      font-family: var(--vscode-font-family);
      font-size: 12px;
      text-anchor: middle;
      pointer-events: none;
    }
    .fl-footer { padding: 6px 16px; font-size: 11px; opacity: 0.6; }
    @keyframes fl-dash {
      to { stroke-dashoffset: -14; }
    }
  </style>
</head>
<body>
  <header class="fl-header">
    <h1>Purs Graphs Fluent Panel</h1>
    <p id="desc">Hover to repel, press and drag a node to pull the graph — the Rust&#8594;WASM spring simulation reacts live.</p>
    <div id="status">loading engine…</div>
  </header>
  <div id="canvas"></div>
  <footer class="fl-footer">Engine: Rust &#8594; WebAssembly (springs + repulsion + pointer well) &#8226; rendered by the PureScript webview.</footer>
  <script nonce='"""
    <> nonce
    <> "' src='"
    <> scriptUri
    <> "'></script>\n</body>\n</html>"
