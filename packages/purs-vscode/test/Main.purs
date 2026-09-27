module Test.VscodeMain where

import Prelude

import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run)
import Vscode.Version (stubActive)

main :: Effect Unit
main = launchAff_ $ run [ consoleReporter ] do
  describe "Vscode.Version" do
    it "resolves the vscode stub through spago's bundler" do
      active <- liftEffect stubActive
      active `shouldEqual` true
