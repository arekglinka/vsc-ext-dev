-- | The PureScript extension host: a full port of `src/extension.ts:47-153`
-- | (the TS module remains the live host until the Task 13 cutover; this
-- | module is proven byte-level behavior-identical by the characterization
-- | fixture diff — see `scripts/fixtures/characterization.json` and the
-- | behavior suite in `host-src/test/Main.purs`).
-- |
-- | Port map (TS line references):
-- |
-- |   * `kindForDocument`  ← `:47-60`  (extension → .graph.json suffix → languageId)
-- |   * `activate`         ← `:62-149` (commands, panel registry, live refresh)
-- |   * `pushUpdate`       ← `:135-141` (per-push config read, fire-and-forget post)
-- |   * HTML template      ← `:155-213`, relocated verbatim in `Host.Html`
-- |
-- | Frozen quirks ported VERBATIM — do not "fix" any of these:
-- |
-- |   * `createWebviewPanel` always gets `beside`; the `viewColumn + 1`
-- |     arithmetic lives only in `reveal` (`:82`, with a `Beside` fallback
-- |     when the editor has no column).
-- |   * The per-panel `onDidChangeTextDocument` listener is pushed to
-- |     `context.subscriptions` and NEVER removed on dispose — after a panel
-- |     closes, a document change still posts to the dead panel (`:114-125`).
-- |   * `kindForDocument`'s `fileName.slice(fileName.lastIndexOf("."))`
-- |     degrades to the LAST CHARACTER for extensionless names (slice(-1)),
-- |     which can never match `[.dot, .gv]` — the languageId fallback is
-- |     what classifies them (`:50`).
-- |   * `fileName.split("/")` has no Windows handling; every preview
-- |     (create or reveal) posts an update; `postMessage` is void-discarded.
-- |
-- | FFI rule: this module uses ONLY the `Vscode.*` bindings — no raw FFI.
module Host.Main
  ( activate
  , kindForDocument
  ) where

import Prelude

import Data.Array (last)
import Data.Maybe (Maybe(..), fromMaybe, isJust, maybe)
import Data.String (Pattern(..), stripSuffix)
import Data.String as Str
import Effect (Effect)
import Effect.Console (log)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Effect.Uncurried (EffectFn1, mkEffectFn1)
import Foreign.Object (Object)
import Foreign.Object as Object
import GraphProtocol (GraphKind(..), WebviewToHost(..), decodeWebviewToHost, encodeHostUpdate, kindToString)
import Host.Html (getHtml, getNonce)
import Vscode.Commands (registerCommand)
import Vscode.Core (ExtensionContext, TextDocument, WebviewPanel, beside, extensionUri, joinPath, pushSubscription, uriToString, viewColumnOne)
import Vscode.WebviewPanel (asWebviewUri, onDidReceiveMessage, panelOnDispose, panelReveal, panelVisible, postMessage, setWebviewHtml, webviewOf)
import Vscode.Window (activeTextEditor, createWebviewPanel, documentFileName, documentLanguageId, documentText, documentUri, editorDocument, editorViewColumn, showErrorMessage)
import Vscode.Workspace (eventDocument, getConfigString, getConfiguration, onDidChangeTextDocument)

-- | VSCode's activation entry point (`export function activate`, :62).
-- | An uncurried `EffectFn1` so the entry shim can re-export it directly as
-- | the extension's `activate`. The TS `deactivate` is empty and optional —
-- | not exported.
activate :: EffectFn1 ExtensionContext Unit
activate = mkEffectFn1 activateImpl

-- | The panel registry (`const panels = new Map<string, WebviewPanel>()`,
-- | :63), keyed by `doc.uri.toString()`. Backed by `Foreign.Object` —
-- | `purescript-maps` is outside the frozen `spago.lock` closure; a
-- | String-keyed map is exactly what the TS uses.
type PanelRegistry = Ref (Object WebviewPanel)

activateImpl :: ExtensionContext -> Effect Unit
activateImpl context = do
  panels <- Ref.new Object.empty
  dotDisposable <- registerCommand "pursGraphs.previewDot" (openPreview context panels Dot)
  graphDisposable <- registerCommand "pursGraphs.previewGraph" (openPreview context panels Graph)
  pushSubscription context dotDisposable
  pushSubscription context graphDisposable

-- | `async function openPreview(kind)` (:65-84) — the command handler body.
-- | Synchronous in effect: the TS `async` wrapper never awaits anything.
openPreview :: ExtensionContext -> PanelRegistry -> GraphKind -> Effect Unit
openPreview context panels kind = do
  editor <- activeTextEditor
  case editor of
    Nothing -> showErrorMessage noEditorMessage
    Just active -> do
      doc <- editorDocument active
      actualKind <- kindForDocument doc
      case actualKind of
        Just k
          | k == kind -> do
              key <- documentUri doc >>= uriToString
              known <- Ref.read panels <#> Object.lookup key
              panel <- case known of
                Just existing -> pure existing
                Nothing -> createPanel context panels doc key
              column <- editorViewColumn active
              panelReveal panel (maybe beside (_ + viewColumnOne) column)
              pushUpdate panel doc
        _ -> showErrorMessage (wrongKindMessage kind)

-- | `function createPanel(doc, kind)` (:86-128) — creates and fully wires a
-- | panel: HTML, registry insert, message handler, dispose handler (registry
-- | delete ONLY — the change listener leak is intentional), live-refresh
-- | subscription.
createPanel :: ExtensionContext -> PanelRegistry -> TextDocument -> String -> Effect WebviewPanel
createPanel context panels doc key = do
  extUri <- extensionUri context
  mediaRoot <- joinPath extUri [ "media" ]
  fileName <- documentFileName doc
  panel <- createWebviewPanel "pursGraphs.preview" ("Preview: " <> splitPop fileName) beside
    { enableScripts: true
    , localResourceRoots: [ mediaRoot ]
    }
  webview <- webviewOf panel
  scriptUri <- joinPath extUri [ "media", "webview.js" ] >>= asWebviewUri webview >>= uriToString
  nonce <- getNonce
  setWebviewHtml webview (getHtml scriptUri nonce)
  Ref.modify_ (Object.insert key panel) panels

  onMessageDisposable <- onDidReceiveMessage webview \payload ->
    case decodeWebviewToHost payload of
      Just (WError errorKind message) ->
        log ("[purs-graphs] " <> kindToString errorKind <> " render error: " <> message)
      _ -> pure unit
  pushSubscription context onMessageDisposable

  disposeDisposable <- panelOnDispose panel (Ref.modify_ (Object.delete key) panels)
  pushSubscription context disposeDisposable

  -- Live-refresh: re-send the source whenever the document changes (:117-125).
  -- The subscription is never disposed — the disposed-panel post leak is part
  -- of the frozen behavior.
  changeDisposable <- onDidChangeTextDocument \event -> do
    eventDoc <- eventDocument event
    eventKey <- documentUri eventDoc >>= uriToString
    when (eventKey == key) do
      visible <- panelVisible panel
      when visible (pushUpdate panel eventDoc)
  pushSubscription context changeDisposable

  pure panel

-- | `function pushUpdate(panel, doc)` (:130-143) — re-reads `kindForDocument`
-- | and the `pursGraphs.dotEngine` config on EVERY push, then void-discards
-- | the `postMessage` Thenable (no `.catch` — parity).
pushUpdate :: WebviewPanel -> TextDocument -> Effect Unit
pushUpdate panel doc = do
  kind <- kindForDocument doc
  case kind of
    Nothing -> pure unit
    Just actualKind -> do
      source <- documentText doc
      fileName <- documentFileName doc
      config <- getConfiguration "pursGraphs"
      engine <- getConfigString config "dotEngine" "dot"
      webview <- webviewOf panel
      postMessage webview
        (encodeHostUpdate { kind: actualKind, source, fileName: splitPop fileName, engine })

-- | `function kindForDocument(doc)` (:47-60) — classification order is
-- | load-bearing: dot extensions (lowercased `slice(lastIndexOf("."))`) →
-- | `.graph.json` suffix → `languageId === "dot"` → Nothing.
-- |
-- | Exported for the behavior suite (the TS helper is module-internal); the
-- | shipped bundle only re-exports `activate`, so this is packaging-neutral.
kindForDocument :: TextDocument -> Effect (Maybe GraphKind)
kindForDocument doc = do
  fileName <- documentFileName doc
  languageId <- documentLanguageId doc
  let
    extension =
      jsSliceFrom (fromMaybe (-1) (Str.lastIndexOf (Pattern ".") fileName)) fileName
  pure
    if Str.toLower extension == ".dot" || Str.toLower extension == ".gv" then Just Dot
    else if isJust (stripSuffix (Pattern ".graph.json") (Str.toLower fileName)) then Just Graph
    else if languageId == "dot" then Just Dot
    else Nothing

-- | JavaScript `s.slice(i)` for the exact call shape `:50` uses — `i` comes
-- | from `lastIndexOf`, so it can be `-1`, and `slice(-1)` means the LAST
-- | character (the negative start is clamped to `length + i`), NOT "drop one
-- | from the front". For an empty string both JS and this port yield `""`.
jsSliceFrom :: Int -> String -> String
jsSliceFrom i s =
  let
    len = Str.length s
    start = if i < 0 then max 0 (len + i) else i
  in
    if start >= len then "" else Str.drop start s

-- | `fileName.split("/").pop()` (:89, :139) — no Windows handling (parity);
-- | `fromMaybe` covers the `?? doc.fileName` fallback (`Data.Array.last` is
-- | `Maybe`, the JS `pop` never is).
splitPop :: String -> String
splitPop fileName = fromMaybe fileName (last (Str.split (Pattern "/") fileName))

noEditorMessage :: String
noEditorMessage = "Purs Graphs: open a .dot/.gv or *.graph.json file first."

-- | The `kind === "dot" ? … : …` ternary in the wrong-kind message (:74-76).
kindPhrase :: GraphKind -> String
kindPhrase = case _ of
  Dot -> "a .dot/.gv file"
  Graph -> "a *.graph.json file"

wrongKindMessage :: GraphKind -> String
wrongKindMessage kind =
  "Purs Graphs: this command previews "
    <> kindPhrase kind
    <> " — the active editor does not look like one."
