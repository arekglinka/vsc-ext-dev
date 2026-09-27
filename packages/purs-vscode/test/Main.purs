module Test.VscodeMain where

import Prelude

import Data.Maybe (Maybe(..), isJust, isNothing)
import Data.Nullable (Nullable, toNullable)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
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

makeDemoDocument :: Effect TextDocument
makeDemoDocument =
  makeTextDocument { fileName: "demo.dot", languageId: "dot", text: "digraph{a->b}" }

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
