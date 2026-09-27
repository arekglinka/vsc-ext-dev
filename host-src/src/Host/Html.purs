-- | Webview HTML/CSP template + nonce generator — VERBATIM relocation of
-- | `src/extension.ts:155-213` (template :158-204, nonce :206-213) into
-- | PureScript as part of the PS-host migration.
-- |
-- | Fidelity contract (byte-exact modulo nonce):
-- |  * The CSP meta is MULTI-LINE and hardcodes `vscode-webview:` in
-- |    img-src/style-src/font-src — there is NO `cspSource` interpolation
-- |    (the original template never used it; verified against :162-167).
-- |  * `'wasm-unsafe-eval'` in script-src is REQUIRED for the inlined
-- |    viz.js WASM (AGENTS.md gotcha) — never "clean up" CSP bytes.
-- |  * Only substitutions: `${nonce}` (2 places: CSP `script-src` and the
-- |    `<script nonce>` attribute) and `${scriptUri}` (the script src).
-- |  * The nonce is a verbatim Math.random port (32 iterations of
-- |    `possible.charAt(Math.floor(Math.random() * possible.length))`).
-- |    No crypto upgrade — documented parity decision (migration plan
-- |    deviation #1).
-- |
-- | Byte-exactness is enforced by the golden-fixture test in
-- | `host-src/test/Main.purs` (frozen from
-- | `scripts/fixtures/characterization.json`, Task 4).
module Host.Html
  ( getHtml
  , getNonce
  ) where

import Prelude

import Data.Array (replicate)
import Data.Int (floor, toNumber)
import Data.Maybe (fromMaybe)
import Data.String.CodeUnits (charAt, fromCharArray, length)
import Data.Traversable (sequence)
import Effect (Effect)

-- | FFI: the ONLY JS piece — the randomness source (documented parity
-- | decision: Math.random, not crypto).
foreign import mathRandom :: Effect Number

nonceAlphabet :: String
nonceAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

randomNonceChar :: Effect Char
randomNonceChar = do
  r <- mathRandom
  let index = floor (r * toNumber (length nonceAlphabet))
  pure $ fromMaybe 'A' (charAt index nonceAlphabet)

-- | Generate a 32-character alphanumeric nonce (`[A-Za-z0-9]`, Math.random
-- | per character — verbatim port of `src/extension.ts:206-213`; do NOT
-- | "upgrade" to crypto).
getNonce :: Effect String
getNonce = fromCharArray <$> sequence (replicate 32 randomNonceChar)

-- | Render the webview HTML.
-- |
-- | Arguments (in order): `scriptUri` — the webview resource URI of
-- | `media/webview.js` (from `webview.asWebviewUri`); `nonce` — a nonce
-- | from `getNonce`.
-- |
-- | Byte-exact pure-string port of the template at
-- | `src/extension.ts:158-204`; see the module header for the fidelity
-- | contract.
getHtml :: String -> String -> String
getHtml scriptUri nonce =
  "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta http-equiv=\"Content-Security-Policy\" content=\"\n    default-src 'none';\n    img-src vscode-webview: data:;\n    style-src vscode-webview: 'unsafe-inline';\n    script-src 'nonce-"
    <> nonce
    <> "' 'wasm-unsafe-eval';\n    font-src vscode-webview:;\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>Purs Graphs Preview</title>\n  <style>\n    body {\n      margin: 0;\n      padding: 12px;\n      font-family: var(--vscode-font-family);\n      color: var(--vscode-editor-foreground);\n      background: var(--vscode-editor-background);\n    }\n    #status {\n      font-size: 11px;\n      opacity: 0.7;\n      min-height: 1.2em;\n      margin-bottom: 8px;\n    }\n    #status.error { color: var(--vscode-errorForeground); opacity: 1; }\n    #canvas svg { max-width: 100%; height: auto; }\n    #canvas .pg-edge { stroke: var(--vscode-editor-foreground); opacity: 0.4; }\n    #canvas .pg-node { fill: var(--vscode-editor-widget-background); stroke: var(--vscode-focusBorder); }\n    #canvas .pg-label {\n      fill: var(--vscode-editor-foreground);\n      font-family: var(--vscode-font-family);\n      font-size: 11px;\n      text-anchor: middle;\n      dominant-baseline: middle;\n      pointer-events: none;\n    }\n  </style>\n</head>\n<body>\n  <div id=\"status\"></div>\n  <div id=\"canvas\"></div>\n  <script nonce=\""
    <> nonce
    <> "\" src=\""
    <> scriptUri
    <> "\"></script>\n</body>\n</html>"
