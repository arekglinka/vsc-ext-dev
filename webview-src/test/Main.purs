module Test.WebviewMain where

import Prelude

import Data.Maybe (Maybe(..))
import Data.String.CodeUnits as CU
import Data.String.Pattern (Pattern(..))
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Aff (launchAff_)
import GraphProtocol (FluentPayload)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (runSpec)
import Webview.Stage (StagePoint, edgeIndicesFor, escapeHtml, fluentStageHtml, nearestNode)

payload :: FluentPayload
payload =
  { nodes:
      [ { id: "a", label: "Alpha" }
      , { id: "b", label: "Be<ta> & \"Co\"" }
      , { id: "c", label: "Gamma" }
      ]
  , edges:
      [ { from: "a", to: "b" }
      , { from: "b", to: "c" }
      , { from: "a", to: "ghost" } -- unknown endpoint must drop
      , { from: "ghost", to: "c" }
      ]
  }

point :: Number -> Number -> StagePoint
point x y = { x, y }

main :: Effect Unit
main = launchAff_ $ runSpec [ consoleReporter ] do
  describe "Webview.Stage » escapeHtml" do
    it "escapes the five innerHTML-unsafe characters" do
      escapeHtml "<a href=\"x\">&' </a>" `shouldEqual`
        "&lt;a href=&quot;x&quot;&gt;&amp;&#39; &lt;/a&gt;"

    it "leaves plain text untouched" do
      escapeHtml "plain 42 text" `shouldEqual` "plain 42 text"

  describe "Webview.Stage » edgeIndicesFor" do
    it "resolves endpoints to indices and drops edges with unknown ids" do
      edgeIndicesFor payload `shouldEqual` [ Tuple 0 1, Tuple 1 2 ]

    it "yields nothing for an edgeless graph" do
      edgeIndicesFor { nodes: payload.nodes, edges: [] } `shouldEqual` []

  describe "Webview.Stage » nearestNode (drag grab target)" do
    let
      nodes =
        [ point 100.0 100.0
        , point 300.0 100.0
        , point 500.0 300.0
        ]

    it "picks the node under the pointer" do
      nearestNode nodes 105.0 98.0 36.0 `shouldEqual` Just 0

    it "picks the nearest of several candidates" do
      nearestNode nodes 310.0 110.0 36.0 `shouldEqual` Just 1

    it "returns Nothing when no node is within the grab radius" do
      nearestNode nodes 100.0 160.0 36.0 `shouldEqual` Nothing

    it "grabs exactly at the radius boundary" do
      nearestNode [ point 0.0 0.0 ] 36.0 0.0 36.0 `shouldEqual` Just 0

  describe "Webview.Stage » fluentStageHtml" do
    it "renders one group per node and one line per resolved edge" do
      let html = fluentStageHtml payload (edgeIndicesFor payload)
      countSubstrings "fluent-n-" html `shouldEqual` 3
      countSubstrings "fluent-e-" html `shouldEqual` 2

    it "anchors the stage svg and escapes node labels" do
      let html = fluentStageHtml payload []
      CU.indexOf (Pattern "<svg id=\"stage\"") html `shouldEqual` Just 0
      CU.contains (Pattern "Be&lt;ta&gt; &amp; &quot;Co&quot;") html `shouldEqual` true

countSubstrings :: String -> String -> Int
countSubstrings needle hay = go 0 hay
  where
  pattern = Pattern needle

  advance s = case CU.indexOf pattern s of
    Just i -> i + CU.length needle
    Nothing -> 0

  go acc s = case CU.indexOf pattern s of
    Just _ -> go (acc + 1) (CU.drop (advance s) s)
    Nothing -> acc
