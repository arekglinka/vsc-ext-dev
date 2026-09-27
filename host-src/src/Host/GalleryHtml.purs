-- | Webview HTML/CSP template for the **Purs Graphs Showcase Gallery**
-- | (`pursGraphs.showcase`). Post-migration feature work — NOT part of the
-- | frozen byte-oracle in `Host.Html` (that template stays verbatim for
-- | previews). This sibling keeps the same security-critical CSP shape:
-- | nonce'd `script-src` + `'wasm-unsafe-eval'` for the inlined viz.js WASM
-- | (AGENTS.md gotcha) and the `vscode-webview:` resource allow-list.
-- |
-- | DOM anchors consumed by `Webview.Main`'s gallery mode:
-- |   * `#nav` — sample list (buttons injected by the webview)
-- |   * `#desc` — selected sample description
-- |   * `#status` — render status / error line (same contract as previews)
-- |   * `#canvas` — rendered SVG (same contract, `pg-*` classes included)
-- |   * `#open-editor` — "Open sample in editor" button
module Host.GalleryHtml
  ( getGalleryHtml
  ) where

import Prelude

-- | Render the showcase gallery HTML. Arguments mirror `Host.Html.getHtml`:
-- | `scriptUri` — the webview resource URI of `media/webview.js`; `nonce` —
-- | from `Host.Html.getNonce` (same 32-char generator, reused).
getGalleryHtml :: String -> String -> String
getGalleryHtml scriptUri nonce =
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
  <title>Purs Graphs Showcase</title>
  <style>
    html, body { height: 100%; }
    body {
      margin: 0;
      font-family: var(--vscode-font-family);
      color: var(--vscode-editor-foreground);
      background: var(--vscode-editor-background);
    }
    #gallery { display: flex; flex-direction: column; height: 100vh; box-sizing: border-box; }
    .pg-header { padding: 12px 16px 8px; border-bottom: 1px solid var(--vscode-panel-border); }
    .pg-header h1 { font-size: 1.05em; font-weight: 600; margin: 0 0 4px; }
    #desc { margin: 0 0 6px; font-size: 12px; opacity: 0.8; min-height: 1.4em; }
    #status { font-size: 11px; opacity: 0.7; min-height: 1.2em; }
    #status.error { color: var(--vscode-errorForeground); opacity: 1; }
    .pg-body { display: flex; flex: 1; min-height: 0; }
    #nav {
      width: 220px;
      flex: none;
      overflow-y: auto;
      padding: 8px;
      display: flex;
      flex-direction: column;
      gap: 4px;
      border-right: 1px solid var(--vscode-panel-border);
      box-sizing: border-box;
    }
    #nav button {
      all: unset;
      box-sizing: border-box;
      display: flex;
      flex-direction: column;
      gap: 2px;
      padding: 8px 10px;
      border-radius: 6px;
      border: 1px solid transparent;
      cursor: pointer;
      color: inherit;
      font-family: inherit;
    }
    #nav button:hover { background: var(--vscode-list-hoverBackground); }
    #nav button.active {
      background: var(--vscode-list-activeSelectionBackground);
      border-color: var(--vscode-focusBorder);
    }
    .pg-nav-title { font-size: 12px; font-weight: 600; }
    .pg-nav-meta { font-size: 10px; opacity: 0.65; text-transform: uppercase; letter-spacing: 0.04em; }
    #canvas { flex: 1; overflow: auto; padding: 16px; }
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
    .pg-footer {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 8px 16px;
      border-top: 1px solid var(--vscode-panel-border);
    }
    #open-editor {
      all: unset;
      box-sizing: border-box;
      padding: 4px 12px;
      border-radius: 4px;
      background: var(--vscode-button-background);
      color: var(--vscode-button-foreground);
      cursor: pointer;
      font-size: 12px;
    }
    #open-editor:hover { background: var(--vscode-button-hoverBackground); }
    .pg-hint { font-size: 11px; opacity: 0.6; }
  </style>
</head>
<body>
  <main id="gallery">
    <header class="pg-header">
      <h1>Purs Graphs Showcase</h1>
      <p id="desc">Loading samples…</p>
      <div id="status"></div>
    </header>
    <div class="pg-body">
      <nav id="nav"></nav>
      <section id="canvas"></section>
    </div>
    <footer class="pg-footer">
      <button id="open-editor" title="Open the selected sample's source in an editor">Open sample in editor</button>
      <span class="pg-hint">DOT samples live-preview with Ctrl+Shift+G once open.</span>
    </footer>
  </main>
  <script nonce='"""
    <> nonce
    <> "' src='"
    <> scriptUri
    <> "'></script>\n</body>\n</html>"
