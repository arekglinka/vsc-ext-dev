module Test.VscodeMain where

import Prelude

import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run)
import Vscode.Core
  ( Disposable
  , ExtensionContext
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

-- Test-side FFI (implemented in test/Main.js): stub drivers that inspect
-- state beyond what the library bindings expose. Deliberately NOT part of
-- Vscode.Core — the library ships zero test scaffolding.
foreign import makeContext :: Effect ExtensionContext
foreign import subscriptionsLength :: ExtensionContext -> Effect Int
foreign import makeFakeDisposable :: Effect Disposable
foreign import stubCommandsLength :: Effect Int
foreign import resetStub :: Effect Unit

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
