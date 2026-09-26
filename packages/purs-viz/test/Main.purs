module Test.VizMain where

import Prelude

import Data.Array (range)
import Data.Array.NonEmpty (cons')
import Data.Either (Either(..), isLeft, isRight)
import Data.Foldable (elem)
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), contains, indexOf, joinWith)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Test.QuickCheck ((===))
import Test.QuickCheck.Arbitrary (class Arbitrary, arbitrary)
import Test.QuickCheck.Gen (chooseInt, elements)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck, quickCheck')
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run)
import Viz (new)
import Viz.Render
  ( Engine(..)
  , RenderOptions
  , defaultRenderOptions
  , engineToString
  , renderJSON
  , renderString
  )

newtype ArbEngine = ArbEngine Engine

instance Arbitrary ArbEngine where
  arbitrary = ArbEngine <$> elements (cons' Dot [ Neato, Circo, Fdp, Twopi ])

newtype ArbDigraph = ArbDigraph String

instance Arbitrary ArbDigraph where
  arbitrary = do
    count <- chooseInt 2 6
    let names = map (\i -> "n" <> show i) (range 1 count)
    pure (ArbDigraph ("digraph { " <> joinWith " -> " names <> " }"))

-- A token that is never a valid DOT graph construct: a numeric literal prefixed
-- with letters, so it can never contain the `graph`/`digraph`/`subgraph` keyword.
newtype ArbGibberish = ArbGibberish String

instance Arbitrary ArbGibberish where
  arbitrary = (\n -> ArbGibberish ("zz" <> show n)) <$> chooseInt 1 1000000

validEngineCodes :: Array String
validEngineCodes = [ "dot", "neato", "circo", "fdp", "twopi" ]

hasSvgPrefix :: String -> Boolean
hasSvgPrefix s =
  indexOf (Pattern "<?xml") s == Just 0 || indexOf (Pattern "<svg") s == Just 0

main :: Effect Unit
main = launchAff_ do
  viz <- new
  run [ consoleReporter ] do
    describe "Viz.Render" do
      it "renders a simple DOT digraph to SVG" do
        let result = renderString viz "digraph { a -> b }" Nothing
        result `shouldSatisfy` isRight
        case result of
          Right svg -> svg `shouldSatisfy` contains (Pattern "<svg")
          Left _ -> pure unit

      it "renders SVG with explicit options" do
        let opts = { format: "svg", engine: Dot } :: RenderOptions
        let result = renderString viz "digraph { a -> b }" (Just opts)
        result `shouldSatisfy` isRight

      it "renders JSON output" do
        let result = renderJSON viz "digraph { a -> b }" Nothing
        result `shouldSatisfy` isRight

      it "returns errors for invalid DOT" do
        let result = renderString viz "this is not valid DOT" Nothing
        result `shouldSatisfy` isLeft

      it "supports different engines (neato)" do
        let opts = { format: "svg", engine: Neato } :: RenderOptions
        let result = renderString viz "digraph { a -> b }" (Just opts)
        result `shouldSatisfy` isRight

    describe "Property tests" do
      it "engineToString always returns a valid code" $
        quickCheck' 100 \(ArbEngine e) -> engineToString e `elem` validEngineCodes

      it "renders well-formed digraphs without error" $
        quickCheck' 30 \(ArbDigraph dot) -> isRight (renderString viz dot Nothing)

      it "SVG output has correct prefix" $
        quickCheck' 20 \(ArbDigraph dot) ->
          case renderString viz dot Nothing of
            Right svg -> hasSvgPrefix svg
            Left _ -> false

      it "rejects malformed DOT" $
        quickCheck \(ArbGibberish s) -> isLeft (renderString viz s Nothing)

      it "default options match explicit defaults" $
        quickCheck' 30 \(ArbDigraph dot) ->
          renderString viz dot Nothing === renderString viz dot (Just defaultRenderOptions)
