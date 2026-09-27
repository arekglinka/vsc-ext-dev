-- | Test suite for the PureScript host:
-- |
-- |  * `Host.Html` — the verbatim relocation of the webview HTML/CSP template
-- |    and nonce generator from `src/extension.ts:155-213`.
-- |  * `Host.Main` — the full behavior suite for the activation port of
-- |    `src/extension.ts:47-153`, driving `activate` against the dev-only
-- |    vscode stub (via `host-src/test/Main.js` FFI) and mirroring the
-- |    characterization steps frozen in `scripts/fixtures/characterization.json`.
-- |
-- | The golden HTML constant below is BYTE-FROZEN from
-- | `scripts/fixtures/characterization.json` field `.panel.html`
-- | (captured from the CURRENT TS host in Task 4, every nonce masked as
-- | `<NONCE>`, scriptUri `vscode-webview-resource://file:///ext/media/webview.js`).
-- | It is the byte-oracle: if `getHtml` output ever differs from it
-- | (modulo nonce), fix the TEMPLATE, never this test. CSP bytes are
-- | security-adjacent — `'wasm-unsafe-eval'` is required for the inlined
-- | viz.js WASM (AGENTS.md gotcha) — so byte-exactness is the only safe bar.
module Test.HostMain where

import Prelude

import Data.Argonaut.Core (Json)
import Data.Array (length)
import Data.Foldable (all)
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), Replacement(..), contains, replaceAll, split)
import Data.String as Str
import Data.String.CodeUnits (toCharArray)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Uncurried (runEffectFn1)
import GraphProtocol (GraphKind(..))
import Host.Html (getHtml, getNonce)
import Host.Main (activate, kindForDocument)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual, shouldNotEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run)
import Vscode.Core (ExtensionContext, TextDocument, TextEditor)

-- Stub-side observation FFI (host-src/test/Main.js).
foreign import data StubPanel :: Type

foreign import resetStub :: Effect Unit
foreign import makeContext :: Effect ExtensionContext
foreign import subscriptionsLength :: ExtensionContext -> Effect Int
foreign import stubCommandIds :: Effect (Array String)
foreign import invokeCommand :: String -> Effect Unit
foreign import makeTextDocument
  :: { fileName :: String, languageId :: String, text :: String } -> Effect TextDocument

foreign import makeFakeEditor :: TextDocument -> Int -> Effect TextEditor

foreign import makeFakeEditorWithoutColumn :: TextDocument -> Effect TextEditor

foreign import setActiveTextEditor :: TextEditor -> Effect Unit
foreign import drainErrorMessages :: Effect (Array String)
foreign import panelsLength :: Effect Int
foreign import panelAt :: Int -> Effect StubPanel
foreign import panelViewType :: StubPanel -> Effect String
foreign import panelTitle :: StubPanel -> Effect String
foreign import panelShowOptions :: StubPanel -> Effect Int
foreign import panelRevealsLength :: StubPanel -> Effect Int
foreign import panelRevealAt :: StubPanel -> Int -> Effect Int
foreign import countNonceRuns :: StubPanel -> Effect Int
foreign import webviewHtmlContains :: StubPanel -> String -> Effect Boolean
foreign import setPanelVisible :: StubPanel -> Boolean -> Effect Unit
foreign import fireDispose :: StubPanel -> Effect Unit
foreign import panelReferenceEquals :: StubPanel -> StubPanel -> Boolean
foreign import emitDocChange :: TextDocument -> Effect Unit
foreign import setConfiguration :: String -> String -> String -> Effect Unit
foreign import fireWebviewMessage :: StubPanel -> Json -> Effect Unit
foreign import errorPayload :: Json
foreign import renderedPayload :: Json
foreign import malformedPayload :: Json
foreign import captureLogs :: Effect Unit -> Effect (Array String)
foreign import postMessagesLength :: Effect Int
foreign import postMessageStringifyAt :: Int -> Effect String

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

-- | Reset the stub and run `activate` against a fresh context.
setup :: Effect ExtensionContext
setup = do
  resetStub
  context <- makeContext
  runEffectFn1 activate context
  pure context

demoDotSpec :: { fileName :: String, languageId :: String, text :: String }
demoDotSpec = { fileName: "demo.dot", languageId: "dot", text: "digraph{a->b}" }

-- Exact wire payloads (JSON.stringify form — key order included).
demoPayload :: String
demoPayload =
  "{\"type\":\"update\",\"kind\":\"dot\",\"source\":\"digraph{a->b}\",\"fileName\":\"demo.dot\",\"engine\":\"dot\"}"

neatoPayload :: String
neatoPayload =
  "{\"type\":\"update\",\"kind\":\"dot\",\"source\":\"digraph{a->b}\",\"fileName\":\"demo.dot\",\"engine\":\"neato\"}"

graphPayload :: String
graphPayload =
  "{\"type\":\"update\",\"kind\":\"graph\",\"source\":\"{\\\"nodes\\\":[]}\",\"fileName\":\"g.graph.json\",\"engine\":\"dot\"}"

gvPayload :: String
gvPayload =
  "{\"type\":\"update\",\"kind\":\"dot\",\"source\":\"digraph{b->c}\",\"fileName\":\"notes.gv\",\"engine\":\"dot\"}"

languageIdPayload :: String
languageIdPayload =
  "{\"type\":\"update\",\"kind\":\"dot\",\"source\":\"digraph{d}\",\"fileName\":\"dotfile\",\"engine\":\"dot\"}"

expectEq :: forall a. Eq a => Show a => Effect a -> a -> Effect Unit
expectEq action expected = action >>= \actual -> actual `shouldEqual` expected

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

  describe "Host.Main" do

    describe "activate" do
      it "registers exactly the two preview commands (fixture order)" do
        _ <- liftEffect setup
        liftEffect $ stubCommandIds `expectEq` [ "pursGraphs.previewDot", "pursGraphs.previewGraph" ]

      it "grows context subscriptions to 2 (both commands; the doc-change listener is per-panel)" do
        context <- liftEffect setup
        liftEffect $ subscriptionsLength context `expectEq` 2

    describe "openPreview guards" do
      it "no active editor → exact error message (both commands)" do
        _ <- liftEffect setup
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        liftEffect $ drainErrorMessages `expectEq`
          [ "Purs Graphs: open a .dot/.gv or *.graph.json file first." ]
        liftEffect $ invokeCommand "pursGraphs.previewGraph"
        liftEffect $ drainErrorMessages `expectEq`
          [ "Purs Graphs: open a .dot/.gv or *.graph.json file first." ]

      it "markdown doc via previewDot → exact wrong-kind message" do
        _ <- liftEffect setup
        readme <- liftEffect $ makeTextDocument
          { fileName: "README.md", languageId: "markdown", text: "# hello" }
        editor <- liftEffect $ makeFakeEditor readme 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        liftEffect $ drainErrorMessages `expectEq`
          [ "Purs Graphs: this command previews a .dot/.gv file — the active editor does not look like one." ]

      it "dot doc via previewGraph → exact wrong-kind message" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewGraph"
        liftEffect $ drainErrorMessages `expectEq`
          [ "Purs Graphs: this command previews a *.graph.json file — the active editor does not look like one." ]

    describe "panel lifecycle" do
      it "preview demo.dot → panel created with fixture title/viewType/showOptions/html; reveal col 1+1" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        liftEffect $ panelsLength `expectEq` 1
        panel <- liftEffect $ panelAt 0
        liftEffect $ panelViewType panel `expectEq` "pursGraphs.preview"
        liftEffect $ panelTitle panel `expectEq` "Preview: demo.dot"
        liftEffect $ panelShowOptions panel `expectEq` (-2)
        liftEffect $ panelRevealAt panel 0 `expectEq` 2
        liftEffect $ countNonceRuns panel `expectEq` 2
        liftEffect $ webviewHtmlContains panel "'wasm-unsafe-eval'" `expectEq` true
        liftEffect $ webviewHtmlContains panel "img-src vscode-webview:" `expectEq` true
        liftEffect $ webviewHtmlContains panel "src=\"vscode-webview-resource://file:///ext/media/webview.js\""
          `expectEq` true

      it "second preview of the same doc → reveal, no new panel, DOES post an update" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        panel <- liftEffect $ panelAt 0
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        liftEffect $ panelsLength `expectEq` 1
        liftEffect $ panelRevealsLength panel `expectEq` 2
        liftEffect $ panelRevealAt panel 1 `expectEq` 2
        liftEffect $ postMessagesLength `expectEq` 2
        liftEffect $ postMessageStringifyAt 1 `expectEq` demoPayload

      it "editor with undefined viewColumn → reveal falls back to Beside (-2)" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        panel <- liftEffect $ panelAt 0
        noColumnEditor <- liftEffect $ makeFakeEditorWithoutColumn demo
        liftEffect $ setActiveTextEditor noColumnEditor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        liftEffect $ panelsLength `expectEq` 1
        liftEffect $ panelRevealsLength panel `expectEq` 2
        liftEffect $ panelRevealAt panel 1 `expectEq` (-2)

    describe "kindForDocument (order-exact port)" do
      it ".gv extension → Dot (extension wins over languageId)" do
        gv <- liftEffect $ makeTextDocument
          { fileName: "notes.gv", languageId: "plaintext", text: "digraph{b->c}" }
        liftEffect $ kindForDocument gv `expectEq` Just Dot

      it "*.graph.json suffix → Graph" do
        graphDoc <- liftEffect $ makeTextDocument
          { fileName: "g.graph.json", languageId: "json", text: "{\"nodes\":[]}" }
        liftEffect $ kindForDocument graphDoc `expectEq` Just Graph

      it "extensionless name with languageId \"dot\" → Dot (slice(-1) edge classifies nothing)" do
        bare <- liftEffect $ makeTextDocument
          { fileName: "dotfile", languageId: "dot", text: "digraph{d}" }
        liftEffect $ kindForDocument bare `expectEq` Just Dot

      it "README.md / markdown → Nothing" do
        readme <- liftEffect $ makeTextDocument
          { fileName: "README.md", languageId: "markdown", text: "# hello" }
        liftEffect $ kindForDocument readme `expectEq` Nothing

    describe "live refresh" do
      it "visible panel: emit → exact update payload" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        liftEffect $ postMessageStringifyAt 0 `expectEq` demoPayload
        liftEffect $ emitDocChange demo
        liftEffect $ postMessagesLength `expectEq` 2
        liftEffect $ postMessageStringifyAt 1 `expectEq` demoPayload

      it "hidden panel: emit → NO new post (visible guard)" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        panel <- liftEffect $ panelAt 0
        liftEffect $ setPanelVisible panel false
        liftEffect $ emitDocChange demo
        liftEffect $ postMessagesLength `expectEq` 1

      it "config pursGraphs.dotEngine=neato → engine in next payload (re-read per push)" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        liftEffect $ setConfiguration "pursGraphs" "dotEngine" "neato"
        liftEffect $ emitDocChange demo
        liftEffect $ postMessagesLength `expectEq` 2
        liftEffect $ postMessageStringifyAt 1 `expectEq` neatoPayload
        liftEffect $ setConfiguration "pursGraphs" "dotEngine" "dot"

      it "graph/gv/languageId docs produce their exact wire payloads" do
        _ <- liftEffect setup
        graphDoc <- liftEffect $ makeTextDocument
          { fileName: "g.graph.json", languageId: "json", text: "{\"nodes\":[]}" }
        graphEditor <- liftEffect $ makeFakeEditor graphDoc 1
        liftEffect $ setActiveTextEditor graphEditor
        liftEffect $ invokeCommand "pursGraphs.previewGraph"
        liftEffect $ postMessageStringifyAt 0 `expectEq` graphPayload
        gv <- liftEffect $ makeTextDocument
          { fileName: "notes.gv", languageId: "plaintext", text: "digraph{b->c}" }
        gvEditor <- liftEffect $ makeFakeEditor gv 2
        liftEffect $ setActiveTextEditor gvEditor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        liftEffect $ postMessagesLength `expectEq` 2
        liftEffect $ postMessageStringifyAt 1 `expectEq` gvPayload
        bare <- liftEffect $ makeTextDocument
          { fileName: "dotfile", languageId: "dot", text: "digraph{d}" }
        bareEditor <- liftEffect $ makeFakeEditor bare 1
        liftEffect $ setActiveTextEditor bareEditor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        liftEffect $ postMessagesLength `expectEq` 3
        liftEffect $ postMessageStringifyAt 2 `expectEq` languageIdPayload

    describe "webview → host messages" do
      it "error message → exact console line" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        panel <- liftEffect $ panelAt 0
        logs <- liftEffect $ captureLogs (fireWebviewMessage panel errorPayload)
        logs `shouldEqual` [ "[purs-graphs] dot render error: bad dot" ]

      it "rendered + malformed messages → silent, no crash, no posts" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        panel <- liftEffect $ panelAt 0
        logs <- liftEffect $ captureLogs do
          fireWebviewMessage panel renderedPayload
          fireWebviewMessage panel malformedPayload
        logs `shouldEqual` []
        liftEffect $ postMessagesLength `expectEq` 1

    describe "dispose / recreate" do
      it "dispose clears the registry; the per-panel change listener LEAKS on purpose (verbatim)" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        panel <- liftEffect $ panelAt 0
        liftEffect $ fireDispose panel
        liftEffect $ panelsLength `expectEq` 1
        liftEffect $ emitDocChange demo
        liftEffect $ postMessagesLength `expectEq` 2
        liftEffect $ postMessageStringifyAt 1 `expectEq` demoPayload

      it "re-preview after dispose → a NEW panel object" do
        _ <- liftEffect setup
        demo <- liftEffect $ makeTextDocument demoDotSpec
        editor <- liftEffect $ makeFakeEditor demo 1
        liftEffect $ setActiveTextEditor editor
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        panel <- liftEffect $ panelAt 0
        liftEffect $ fireDispose panel
        liftEffect $ invokeCommand "pursGraphs.previewDot"
        liftEffect $ panelsLength `expectEq` 2
        newPanel <- liftEffect $ panelAt 1
        liftEffect $ pure (panelReferenceEquals newPanel panel) `expectEq` false
        liftEffect $ panelRevealsLength newPanel `expectEq` 1
        liftEffect $ postMessagesLength `expectEq` 2

