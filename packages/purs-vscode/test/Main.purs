module Test.VscodeMain where

import Prelude

import Data.Argonaut.Core (Json, jsonNull, stringify, toObject, toString)
import Data.Argonaut.Parser (jsonParser)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), isJust, isNothing)
import Data.Nullable (Nullable, toNullable)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Foreign.Object (lookup)
import Test.Spec (describe, it)
import Test.Spec.Assertions (fail, shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run)
import Vscode.Commands (registerCommand)
import Vscode.Core
  ( Disposable
  , ExtensionContext
  , TextDocument
  , TextEditor
  , ViewColumn
  , Webview
  , WebviewPanel
  , beside
  , dispose
  , extensionUri
  , joinPath
  , pushSubscription
  , unViewColumn
  , uriToString
  , viewColumnOne
  , viewColumnThree
  , viewColumnTwo
  )
import Vscode.Version (stubActive)
import Vscode.WebviewPanel
  ( asWebviewUri
  , onDidReceiveMessage
  , panelOnDispose
  , panelReveal
  , panelVisible
  , postMessage
  , setWebviewHtml
  , webviewOf
  )
import Vscode.Window
  ( PanelOptions
  , activeTextEditor
  , createWebviewPanel
  , documentFileName
  , documentLanguageId
  , documentText
  , documentUri
  , editorDocument
  , editorViewColumn
  , showErrorMessage
  )
import Vscode.Workspace
  ( eventDocument
  , getConfigString
  , getConfiguration
  , onDidChangeTextDocument
  )

-- Test-side FFI (implemented in test/Main.js): stub drivers that inspect
-- state beyond what the library bindings expose. Deliberately NOT part of
-- Vscode.Core — the library ships zero test scaffolding.
foreign import makeContext :: Effect ExtensionContext
foreign import subscriptionsLength :: ExtensionContext -> Effect Int
foreign import makeFakeDisposable :: Effect Disposable
foreign import stubCommandsLength :: Effect Int
foreign import resetStub :: Effect Unit

foreign import makeTextDocument
  :: { fileName :: String, languageId :: String, text :: String } -> Effect TextDocument

-- `Nullable ViewColumn` crosses the FFI as a raw number or null: ViewColumn is
-- a newtype over Int (erased at runtime) and Nullable is null-or-value.
foreign import makeFakeEditor :: TextDocument -> Nullable ViewColumn -> Effect TextEditor
foreign import setActiveTextEditor :: Nullable TextEditor -> Effect Unit
foreign import errorMessagesLength :: Effect Int
foreign import errorMessageAt :: Int -> Effect String
foreign import panelsLength :: Effect Int
foreign import panelViewType :: WebviewPanel -> Effect String
foreign import panelTitle :: WebviewPanel -> Effect String
foreign import panelShowOptions :: WebviewPanel -> Effect ViewColumn
foreign import panelEnableScripts :: WebviewPanel -> Effect Boolean
foreign import panelLocalResourceRootsLength :: WebviewPanel -> Effect Int
foreign import commandsFind :: String -> Effect Boolean
foreign import invokeCommand :: String -> Effect Unit

-- --- Workspace drivers (implemented in test/Main.js) ---

foreign import setConfiguration :: String -> String -> String -> Effect Unit
foreign import emitDocChange :: TextDocument -> Effect Unit
foreign import docChangeListenersLength :: Effect Int

-- --- WebviewPanel drivers (implemented in test/Main.js) ---

foreign import panelRevealsLength :: WebviewPanel -> Effect Int
foreign import panelRevealAt :: WebviewPanel -> Int -> Effect Int
foreign import setPanelVisible :: WebviewPanel -> Boolean -> Effect Unit
foreign import fireDispose :: WebviewPanel -> Effect Unit
foreign import disposeListenersLength :: Effect Int
foreign import messageListenersLength :: Effect Int
foreign import fireWebviewMessage :: WebviewPanel -> Json -> Effect Unit
foreign import webviewHtml :: Webview -> Effect String
foreign import postMessagesLength :: Effect Int
foreign import postMessageStringifyAt :: Int -> Effect String

makeDemoDocument :: Effect TextDocument
makeDemoDocument =
  makeTextDocument { fileName: "demo.dot", languageId: "dot", text: "digraph{a->b}" }

-- A panel exactly as Host.Main will create it (extension.ts:87-95): stub
-- viewType/title plus options {enableScripts, localResourceRoots:[…/media]}.
makeDemoPanel :: Effect WebviewPanel
makeDemoPanel = do
  ctx <- makeContext
  base <- extensionUri ctx
  media <- joinPath base [ "media" ]
  createWebviewPanel "pursGraphs.preview" "Preview: demo.dot" beside
    { enableScripts: true, localResourceRoots: [ media ] }

-- The exact wire shape Host.Main will post (extension.ts:135-141), kept as a
-- literal so the stringify comparison pins the key order too.
updatePayloadLiteral :: String
updatePayloadLiteral =
  """{"type":"update","kind":"dot","source":"digraph{a->b}","fileName":"demo.dot","engine":"dot"}"""

-- A webview→host error message, the one payload the host acts on
-- (extension.ts:99-112).
errorPayloadLiteral :: String
errorPayloadLiteral =
  """{"type":"error","kind":"dot","message":"bad dot"}"""

parseJsonLiteral :: String -> Effect Json
parseJsonLiteral literal = case jsonParser literal of
  Right json -> pure json
  Left err -> do
    fail ("test literal failed to parse: " <> err)
    pure jsonNull

main :: Effect Unit
main = launchAff_ $ run [ consoleReporter ] do
  describe "Vscode.Version" do
    it "resolves the vscode stub through spago's bundler" do
      active <- liftEffect stubActive
      active `shouldEqual` true

  -- Drives the dev-only stub (node_modules/vscode). Test-only FFI helpers live
  -- in test/Main.js — never in src/, so the library ships zero test glue.
  describe "Vscode.Core" do
    it "pushSubscription appends the disposable to context.subscriptions" do
      ctx <- liftEffect makeContext
      d <- liftEffect makeFakeDisposable
      liftEffect $ pushSubscription ctx d
      n <- liftEffect (subscriptionsLength ctx)
      n `shouldEqual` 1

    it "joinPath extends a Uri with the given path segments" do
      ctx <- liftEffect makeContext
      base <- liftEffect (extensionUri ctx)
      media <- liftEffect (joinPath base [ "media" ])
      s <- liftEffect (uriToString media)
      s `shouldEqual` "file:///ext/media"

    it "extensionUri exposes the context's extension Uri" do
      ctx <- liftEffect makeContext
      uri <- liftEffect (extensionUri ctx)
      s <- liftEffect (uriToString uri)
      s `shouldEqual` "file:///ext"

    -- Core has no Disposable factory by design (registration APIs from later
    -- modules produce them). The stub's commands.registerCommand already
    -- exists and returns a real stub Disposable whose disposal is observable
    -- via __stub.commands — so disposal is asserted end-to-end here.
    it "dispose releases a stub disposable (command registration removed)" do
      liftEffect resetStub
      d <- liftEffect makeFakeDisposable
      registered <- liftEffect stubCommandsLength
      registered `shouldEqual` 1
      liftEffect (dispose d)
      remaining <- liftEffect stubCommandsLength
      remaining `shouldEqual` 0

    it "ViewColumn constants carry their numeric vscode values" do
      (unViewColumn beside) `shouldEqual` (-2)
      (unViewColumn viewColumnOne) `shouldEqual` 1
      (unViewColumn viewColumnTwo) `shouldEqual` 2
      (unViewColumn viewColumnThree) `shouldEqual` 3
      -- Reveal's `viewColumn + 1` arithmetic (extension.ts:82) must work:
      (unViewColumn (viewColumnOne + viewColumnOne)) `shouldEqual` 2

  describe "Vscode.Window" do
    it "activeTextEditor exposes the editor set on the stub (Just)" do
      liftEffect resetStub
      doc <- liftEffect makeDemoDocument
      editor <- liftEffect (makeFakeEditor doc (toNullable (Just viewColumnOne)))
      liftEffect (setActiveTextEditor (toNullable (Just editor)))
      result <- liftEffect activeTextEditor
      isJust result `shouldEqual` true
      case result of
        Just ed -> do
          d <- liftEffect (editorDocument ed)
          name <- liftEffect (documentFileName d)
          name `shouldEqual` "demo.dot"
        Nothing -> fail "expected an active editor"

    it "activeTextEditor is Nothing when the stub editor is cleared" do
      liftEffect resetStub
      liftEffect (setActiveTextEditor (toNullable Nothing))
      result <- liftEffect activeTextEditor
      isNothing result `shouldEqual` true

    it "showErrorMessage records the message verbatim" do
      liftEffect resetStub
      liftEffect $ showErrorMessage "boom"
      n <- liftEffect errorMessagesLength
      n `shouldEqual` 1
      msg <- liftEffect (errorMessageAt 0)
      msg `shouldEqual` "boom"

    -- extension.ts:87-95 always passes ViewColumn.Beside as showOptions and
    -- options {enableScripts: true, localResourceRoots: [joinPath extUri
    -- "media"]} — bind exactly that shape; the stub echoes everything back.
    it "createWebviewPanel passes viewType, title, showOptions and options through" do
      liftEffect resetStub
      ctx <- liftEffect makeContext
      base <- liftEffect (extensionUri ctx)
      media <- liftEffect (joinPath base [ "media" ])
      panel <- liftEffect
        $ createWebviewPanel "pursGraphs.preview" "Preview: demo.dot" beside
            { enableScripts: true, localResourceRoots: [ media ] }
      vt <- liftEffect (panelViewType panel)
      vt `shouldEqual` "pursGraphs.preview"
      t <- liftEffect (panelTitle panel)
      t `shouldEqual` "Preview: demo.dot"
      showOptions <- liftEffect (panelShowOptions panel)
      unViewColumn showOptions `shouldEqual` (-2)
      scripts <- liftEffect (panelEnableScripts panel)
      scripts `shouldEqual` true
      roots <- liftEffect (panelLocalResourceRootsLength panel)
      roots `shouldEqual` 1
      n <- liftEffect panelsLength
      n `shouldEqual` 1

    it "editorDocument / editorViewColumn expose the editor's document and column" do
      liftEffect resetStub
      doc <- liftEffect makeDemoDocument
      editor <- liftEffect (makeFakeEditor doc (toNullable (Just viewColumnOne)))
      liftEffect (setActiveTextEditor (toNullable (Just editor)))
      result <- liftEffect activeTextEditor
      case result of
        Just ed -> do
          d <- liftEffect (editorDocument ed)
          name <- liftEffect (documentFileName d)
          name `shouldEqual` "demo.dot"
          col <- liftEffect (editorViewColumn ed)
          col `shouldEqual` Just viewColumnOne
        Nothing -> fail "expected an active editor"

    it "editorViewColumn is Nothing when the editor has no column" do
      liftEffect resetStub
      doc <- liftEffect makeDemoDocument
      editor <- liftEffect (makeFakeEditor doc (toNullable Nothing))
      col <- liftEffect (editorViewColumn editor)
      col `shouldEqual` (Nothing :: Maybe ViewColumn)

    it "document accessors echo the stub document's fields" do
      liftEffect resetStub
      doc <- liftEffect makeDemoDocument
      name <- liftEffect (documentFileName doc)
      name `shouldEqual` "demo.dot"
      lang <- liftEffect (documentLanguageId doc)
      lang `shouldEqual` "dot"
      text <- liftEffect (documentText doc)
      text `shouldEqual` "digraph{a->b}"
      uri <- liftEffect (documentUri doc)
      s <- liftEffect (uriToString uri)
      s `shouldEqual` "file:///ws/demo.dot"

  describe "Vscode.Commands" do
    it "registerCommand records the command id with the stub" do
      liftEffect resetStub
      _ <- liftEffect $ registerCommand "pursGraphs.previewDot" (pure unit)
      found <- liftEffect (commandsFind "pursGraphs.previewDot")
      found `shouldEqual` true
      n <- liftEffect stubCommandsLength
      n `shouldEqual` 1

    it "invoking the stub handler runs the registered Effect" do
      liftEffect resetStub
      ref <- liftEffect (Ref.new 0)
      _ <- liftEffect $ registerCommand "pursGraphs.previewDot" (Ref.modify_ (_ + 1) ref)
      liftEffect (invokeCommand "pursGraphs.previewDot")
      count <- liftEffect (Ref.read ref)
      count `shouldEqual` 1

    it "disposing the returned disposable removes the registration" do
      liftEffect resetStub
      d <- liftEffect $ registerCommand "pursGraphs.previewDot" (pure unit)
      liftEffect (dispose d)
      gone <- liftEffect (commandsFind "pursGraphs.previewDot")
      gone `shouldEqual` false

  -- extension.ts:117-125 consumes the doc-change event as
  -- event.document.uri.toString() for the live-refresh guard, and :140 is the
  -- one config read (3-arg get with default). Both flows are pinned here.
  describe "Vscode.Workspace" do
    it "getConfigString returns the default when no config is set" do
      liftEffect resetStub
      cfg <- liftEffect (getConfiguration "pursGraphs")
      engine <- liftEffect (getConfigString cfg "dotEngine" "dot")
      engine `shouldEqual` "dot"

    it "getConfigString returns the stub-configured override" do
      liftEffect resetStub
      liftEffect (setConfiguration "pursGraphs" "dotEngine" "neato")
      cfg <- liftEffect (getConfiguration "pursGraphs")
      engine <- liftEffect (getConfigString cfg "dotEngine" "dot")
      engine `shouldEqual` "neato"

    it "onDidChangeTextDocument delivers the event document to the handler" do
      liftEffect resetStub
      doc <- liftEffect makeDemoDocument
      received <- liftEffect (Ref.new (Nothing :: Maybe String))
      _ <- liftEffect $ onDidChangeTextDocument \event -> do
        eventDoc <- eventDocument event
        uri <- documentUri eventDoc
        s <- uriToString uri
        Ref.write (Just s) received
      liftEffect (emitDocChange doc)
      result <- liftEffect (Ref.read received)
      result `shouldEqual` Just "file:///ws/demo.dot"

    it "disposing the onDidChangeTextDocument disposable unregisters the handler" do
      liftEffect resetStub
      doc <- liftEffect makeDemoDocument
      received <- liftEffect (Ref.new (Nothing :: Maybe String))
      d <- liftEffect $ onDidChangeTextDocument \event -> do
        eventDoc <- eventDocument event
        uri <- documentUri eventDoc
        s <- uriToString uri
        Ref.write (Just s) received
      listeners <- liftEffect docChangeListenersLength
      listeners `shouldEqual` 1
      liftEffect (dispose d)
      listenersAfter <- liftEffect docChangeListenersLength
      listenersAfter `shouldEqual` 0
      liftEffect (emitDocChange doc)
      result <- liftEffect (Ref.read received)
      result `shouldEqual` Nothing

  -- extension.ts:82 (reveal +1/Beside), :118 (visible guard), :114 (dispose),
  -- :96 (html set), :142 (void-discarded postMessage), :156 (asWebviewUri) and
  -- :99-112 (message subscription) — the full panel lifecycle Host.Main needs.
  describe "Vscode.WebviewPanel" do
    it "panelReveal records the requested columns" do
      liftEffect resetStub
      panel <- liftEffect makeDemoPanel
      liftEffect $ panelReveal panel viewColumnTwo
      liftEffect $ panelReveal panel beside
      n <- liftEffect (panelRevealsLength panel)
      n `shouldEqual` 2
      first <- liftEffect (panelRevealAt panel 0)
      first `shouldEqual` 2
      second <- liftEffect (panelRevealAt panel 1)
      second `shouldEqual` (-2)

    it "panelVisible tracks the panel's live-refresh guard state" do
      liftEffect resetStub
      panel <- liftEffect makeDemoPanel
      visible <- liftEffect (panelVisible panel)
      visible `shouldEqual` true
      liftEffect (setPanelVisible panel false)
      hidden <- liftEffect (panelVisible panel)
      hidden `shouldEqual` false

    it "panelOnDispose fires the handler through the stub's dispose listeners" do
      liftEffect resetStub
      panel <- liftEffect makeDemoPanel
      ref <- liftEffect (Ref.new 0)
      _ <- liftEffect $ panelOnDispose panel (Ref.modify_ (_ + 1) ref)
      liftEffect (fireDispose panel)
      count <- liftEffect (Ref.read ref)
      count `shouldEqual` 1

    it "disposing the panelOnDispose disposable unregisters the handler" do
      liftEffect resetStub
      panel <- liftEffect makeDemoPanel
      ref <- liftEffect (Ref.new 0)
      d <- liftEffect $ panelOnDispose panel (Ref.modify_ (_ + 1) ref)
      liftEffect (dispose d)
      listeners <- liftEffect disposeListenersLength
      listeners `shouldEqual` 0
      liftEffect (fireDispose panel)
      count <- liftEffect (Ref.read ref)
      count `shouldEqual` 0

    it "setWebviewHtml records the HTML verbatim" do
      liftEffect resetStub
      panel <- liftEffect makeDemoPanel
      wv <- liftEffect (webviewOf panel)
      liftEffect $ setWebviewHtml wv "<h1>x</h1>"
      html <- liftEffect (webviewHtml wv)
      html `shouldEqual` "<h1>x</h1>"

    -- Json IS the raw JS value under the FFI (argonaut 7.x): the stub records
    -- the exact object PS posted — deep-equality asserted via stringify, key
    -- order included. No .catch/Aff wrapper: the Thenable is discarded
    -- (parity with `void` at extension.ts:142).
    it "postMessage passes the argonaut Json through as the raw JS value" do
      liftEffect resetStub
      panel <- liftEffect makeDemoPanel
      wv <- liftEffect (webviewOf panel)
      payload <- liftEffect (parseJsonLiteral updatePayloadLiteral)
      liftEffect $ postMessage wv payload
      n <- liftEffect postMessagesLength
      n `shouldEqual` 1
      recorded <- liftEffect (postMessageStringifyAt 0)
      recorded `shouldEqual` updatePayloadLiteral

    it "asWebviewUri rewrites the Uri into a webview resource Uri" do
      liftEffect resetStub
      panel <- liftEffect makeDemoPanel
      wv <- liftEffect (webviewOf panel)
      ctx <- liftEffect makeContext
      base <- liftEffect (extensionUri ctx)
      media <- liftEffect (joinPath base [ "media", "webview.js" ])
      resource <- liftEffect (asWebviewUri wv media)
      s <- liftEffect (uriToString resource)
      s `shouldEqual` "vscode-webview-resource://file:///ext/media/webview.js"

    -- The handler receives the raw JS payload AS Json for protocol decoding;
    -- fidelity is proven twice: stringify round-trip + field decode.
    it "onDidReceiveMessage delivers the raw JS payload to the handler as Json" do
      liftEffect resetStub
      panel <- liftEffect makeDemoPanel
      wv <- liftEffect (webviewOf panel)
      received <- liftEffect (Ref.new (Nothing :: Maybe Json))
      _ <- liftEffect $ onDidReceiveMessage wv \msg -> Ref.write (Just msg) received
      payload <- liftEffect (parseJsonLiteral errorPayloadLiteral)
      liftEffect (fireWebviewMessage panel payload)
      result <- liftEffect (Ref.read received)
      case result of
        Nothing -> fail "handler was not invoked"
        Just msg -> do
          stringify msg `shouldEqual` errorPayloadLiteral
          case (toObject msg >>= lookup "type") >>= toString of
            Just t -> t `shouldEqual` "error"
            Nothing -> fail "payload lost its 'type' field crossing the FFI"

    it "disposing the onDidReceiveMessage disposable unregisters the listener" do
      liftEffect resetStub
      panel <- liftEffect makeDemoPanel
      wv <- liftEffect (webviewOf panel)
      d <- liftEffect $ onDidReceiveMessage wv \_ -> pure unit
      listeners <- liftEffect messageListenersLength
      listeners `shouldEqual` 1
      liftEffect (dispose d)
      listenersAfter <- liftEffect messageListenersLength
      listenersAfter `shouldEqual` 0
