-- | Test suite for `Host.Html` — the verbatim relocation of the webview
-- | HTML/CSP template and nonce generator from `src/extension.ts:155-213`.
-- |
-- | The golden constant below is BYTE-FROZEN from
-- | `scripts/fixtures/characterization.json` field `.panel.html`
-- | (captured from the CURRENT TS host in Task 4, every nonce masked as
-- | `<NONCE>`, scriptUri `vscode-webview-resource://file:///ext/media/webview.js`).
-- | It is the byte-oracle: if `getHtml` output ever differs from it
-- | (modulo nonce), fix the TEMPLATE, never this test. CSP bytes are
-- | security-adjacent — `'wasm-unsafe-eval'` is required for the inlined
-- | viz.js WASM (AGENTS.md gotcha) — so byte-exactness is the only safe bar.
module Test.HostMain where

import Prelude

import Data.Array (length)
import Data.Foldable (all)
import Data.String (Pattern(..), Replacement(..), contains, replaceAll, split)
import Data.String as Str
import Data.String.CodeUnits (toCharArray)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Host.Html (getHtml, getNonce)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual, shouldNotEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run)

-- | Fixed nonce for golden substitution (32 chars from `[A-Za-z0-9]`).
-- | (Plan text suggested "abcdefABCDEF0123456789abcdef12", which is only
-- | 30 chars — lengthened to a true 32-char nonce; value is arbitrary.)
fixedNonce :: String
fixedNonce = "abcdefABCDEF0123456789abcdef1234"

-- | Byte-frozen golden HTML from scripts/fixtures/characterization.json
-- | (.panel.html, Task 4) with every nonce masked as `<NONCE>`.
goldenHtml :: String
goldenHtml =
  "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta http-equiv=\"Content-Security-Policy\" content=\"\n    default-src 'none';\n    img-src vscode-webview: data:;\n    style-src vscode-webview: 'unsafe-inline';\n    script-src 'nonce-<NONCE>' 'wasm-unsafe-eval';\n    font-src vscode-webview:;\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>Purs Graphs Preview</title>\n  <style>\n    body {\n      margin: 0;\n      padding: 12px;\n      font-family: var(--vscode-font-family);\n      color: var(--vscode-editor-foreground);\n      background: var(--vscode-editor-background);\n    }\n    #status {\n      font-size: 11px;\n      opacity: 0.7;\n      min-height: 1.2em;\n      margin-bottom: 8px;\n    }\n    #status.error { color: var(--vscode-errorForeground); opacity: 1; }\n    #canvas svg { max-width: 100%; height: auto; }\n    #canvas .pg-edge { stroke: var(--vscode-editor-foreground); opacity: 0.4; }\n    #canvas .pg-node { fill: var(--vscode-editor-widget-background); stroke: var(--vscode-focusBorder); }\n    #canvas .pg-label {\n      fill: var(--vscode-editor-foreground);\n      font-family: var(--vscode-font-family);\n      font-size: 11px;\n      text-anchor: middle;\n      dominant-baseline: middle;\n      pointer-events: none;\n    }\n  </style>\n</head>\n<body>\n  <div id=\"status\"></div>\n  <div id=\"canvas\"></div>\n  <script nonce=\"<NONCE>\" src=\"vscode-webview-resource://file:///ext/media/webview.js\"></script>\n</body>\n</html>"

-- | Count non-overlapping occurrences of a substring.
countOccurrences :: String -> String -> Int
countOccurrences needle hay = length (split (Pattern needle) hay) - 1

isNonceChar :: Char -> Boolean
isNonceChar c =
  (c >= 'A' && c <= 'Z')
    || (c >= 'a' && c <= 'z')
    || (c >= '0' && c <= '9')

main :: Effect Unit
main = launchAff_ $ run [ consoleReporter ] do
  describe "Host.Html" do

    describe "getHtml (golden fixture)" do
      it "reproduces the captured TS-host HTML byte-for-byte (modulo nonce)" do
        let
          rendered = getHtml "vscode-webview-resource://file:///ext/media/webview.js" fixedNonce
          expected = replaceAll (Pattern "<NONCE>") (Replacement fixedNonce) goldenHtml
        rendered `shouldEqual` expected

      it "substitutes the nonce exactly twice (CSP meta + script tag)" do
        let
          rendered = getHtml "vscode-webview-resource://file:///ext/media/webview.js" fixedNonce
        countOccurrences fixedNonce rendered `shouldEqual` 2

      it "keeps the security-critical CSP directives verbatim" do
        let
          rendered = getHtml "vscode-webview-resource://file:///ext/media/webview.js" fixedNonce
        contains (Pattern "'wasm-unsafe-eval'") rendered `shouldEqual` true
        contains (Pattern "img-src vscode-webview:") rendered `shouldEqual` true
        contains (Pattern "style-src vscode-webview: 'unsafe-inline'") rendered `shouldEqual` true
        contains (Pattern "font-src vscode-webview:") rendered `shouldEqual` true

      it "contains the contracted DOM anchors" do
        let
          rendered = getHtml "vscode-webview-resource://x/media/webview.js" fixedNonce
        contains (Pattern "<!DOCTYPE html>") rendered `shouldEqual` true
        contains (Pattern "<title>Purs Graphs Preview</title>") rendered `shouldEqual` true
        contains (Pattern "id=\"status\"") rendered `shouldEqual` true
        contains (Pattern "id=\"canvas\"") rendered `shouldEqual` true

      it "interpolates the script URI verbatim" do
        let
          rendered = getHtml "vscode-webview-resource://x/media/webview.js" fixedNonce
        contains (Pattern "src=\"vscode-webview-resource://x/media/webview.js\"") rendered
          `shouldEqual` true

    describe "getNonce" do
      it "generates two different nonces" do
        n1 <- liftEffect getNonce
        n2 <- liftEffect getNonce
        n1 `shouldNotEqual` n2

      it "matches the 32-char [A-Za-z0-9] shape (verbatim Math.random port)" do
        n <- liftEffect getNonce
        Str.length n `shouldEqual` 32
        all isNonceChar (toCharArray n) `shouldEqual` true

