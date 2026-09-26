module Test.DagreMain where

import Prelude

import Dagre.Graph
  ( Graph
  , NodeOptions
  , Position
  , RankDir(..)
  , dimensions
  , layout
  , new
  , nodeIds
  , nodePosition
  , rankDirToString
  , setEdge
  , setNode
  , setRankDir
  ) as Graph
import Data.Array (drop, mapMaybe, range, sort, zip)
import Data.Array.NonEmpty (cons')
import Data.Foldable (elem, for_)
import Data.Maybe (Maybe(..), isJust)
import Data.Traversable (traverse, traverse_)
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Test.QuickCheck (Result(..), (===))
import Test.QuickCheck.Arbitrary (class Arbitrary, arbitrary)
import Test.QuickCheck.Gen (Gen, choose, chooseInt, elements, randomSample')
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck')
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run)

nodes :: Array Graph.NodeOptions
nodes =
  [ { id: "source", width: 100.0, height: 40.0, label: "source" }
  , { id: "compile", width: 100.0, height: 40.0, label: "compile" }
  , { id: "link", width: 100.0, height: 40.0, label: "link" }
  , { id: "test", width: 100.0, height: 40.0, label: "test" }
  , { id: "package", width: 100.0, height: 40.0, label: "package" }
  ]

edges :: Array { source :: String, target :: String }
edges =
  [ { source: "source", target: "compile" }
  , { source: "compile", target: "link" }
  , { source: "link", target: "test" }
  , { source: "test", target: "package" }
  ]

buildGraph :: Effect Graph.Graph
buildGraph = do
  g <- Graph.new
  Graph.setRankDir Graph.TopBottom g
  traverse_ (\n -> Graph.setNode n g) nodes
  traverse_ (\e -> Graph.setEdge e g) edges
  pure g

-- QuickCheck generators for property tests.
--
-- dagre's graph API is Effect-typed, and this QuickCheck version has no monadic
-- `Testable` instance, so the graph properties below draw random inputs through
-- `randomSample'` (QuickCheck's own sampler) and assert in `Aff` rather than
-- going through `quickCheck'` directly. The pure `rankDirToString` property
-- uses `quickCheck'` for full spec integration.

newtype ArbRank = ArbRank Graph.RankDir

instance Arbitrary ArbRank where
  arbitrary =
    ArbRank
      <$> elements (cons' Graph.TopBottom [ Graph.BottomTop, Graph.LeftRight, Graph.RightLeft ])

newtype ArbNodes = ArbNodes (Array Graph.NodeOptions)

instance Arbitrary ArbNodes where
  arbitrary = do
    count <- chooseInt 1 6
    nodes <- traverse mkNode (map (\i -> "n" <> show i) (range 1 count))
    pure (ArbNodes nodes)

newtype ArbGraphSpec = ArbGraphSpec
  { nodes :: Array Graph.NodeOptions
  , edges :: Array { source :: String, target :: String }
  }

instance Arbitrary ArbGraphSpec where
  arbitrary = do
    count <- chooseInt 2 6
    let ids = map (\i -> "n" <> show i) (range 1 count)
    nodes <- traverse mkNode ids
    let edges = map (\(Tuple s t) -> { source: s, target: t }) (zip ids (drop 1 ids))
    pure (ArbGraphSpec { nodes, edges })

mkNode :: String -> Gen Graph.NodeOptions
mkNode id = do
  w <- choose 10.0 200.0
  h <- choose 10.0 100.0
  pure { id, width: w, height: h, label: id }

buildNodesGraph :: Array Graph.NodeOptions -> Effect Graph.Graph
buildNodesGraph ns = do
  g <- Graph.new
  traverse_ (\n -> Graph.setNode n g) ns
  pure g

buildSpec
  :: { nodes :: Array Graph.NodeOptions, edges :: Array { source :: String, target :: String } }
  -> Effect Graph.Graph
buildSpec spec = do
  g <- Graph.new
  traverse_ (\n -> Graph.setNode n g) spec.nodes
  traverse_ (\e -> Graph.setEdge e g) spec.edges
  pure g

positionsOf
  :: { nodes :: Array Graph.NodeOptions, edges :: Array { source :: String, target :: String } }
  -> Effect (Array { id :: String, pos :: Graph.Position })
positionsOf spec = do
  g <- buildSpec spec
  Graph.layout g
  pairs <- traverse (\n -> Graph.nodePosition n.id g) spec.nodes
  let indexed = zip (map _.id spec.nodes) pairs
  pure (mapMaybe (\(Tuple id mp) -> map (\p -> { id, pos: p }) mp) indexed)

isSuccess :: Result -> Boolean
isSuccess Success = true
isSuccess (Failed _) = false

validRankCodes :: Array String
validRankCodes = [ "TB", "BT", "LR", "RL" ]

main :: Effect Unit
main = launchAff_ $ run [ consoleReporter ] do
  describe "Dagre.Graph" do
    it "creates a graph and lists all node ids" do
      g <- liftEffect buildGraph
      ids <- liftEffect $ Graph.nodeIds g
      ids `shouldEqual` map _.id nodes

    it "computes positions for all nodes after layout" do
      g <- liftEffect buildGraph
      liftEffect $ Graph.layout g
      pos <- liftEffect $ Graph.nodePosition "compile" g
      pos `shouldSatisfy` isJust

    it "returns Nothing for a non-existent node" do
      g <- liftEffect buildGraph
      liftEffect $ Graph.layout g
      pos <- liftEffect $ Graph.nodePosition "nonexistent" g
      pos `shouldEqual` Nothing

    it "computes graph dimensions after layout" do
      g <- liftEffect buildGraph
      liftEffect $ Graph.layout g
      dims <- liftEffect $ Graph.dimensions g
      dims `shouldSatisfy` isJust

    it "assigns the first node a y-coordinate at or near the top rank" do
      g <- liftEffect buildGraph
      liftEffect $ Graph.layout g
      srcPos <- liftEffect $ Graph.nodePosition "source" g
      pkgPos <- liftEffect $ Graph.nodePosition "package" g
      case srcPos, pkgPos of
        Just s, Just p -> s.y `shouldSatisfy` (_ <= p.y)
        _, _ -> pure unit

    describe "Property tests" do
      it "rankDirToString always returns a valid code" $
        quickCheck' 100 \(ArbRank dir) -> Graph.rankDirToString dir `elem` validRankCodes

      it "nodeIds returns every inserted id" do
        samples <- liftEffect $ randomSample' 50 (arbitrary :: Gen ArbNodes)
        for_ samples \(ArbNodes ns) -> do
          g <- liftEffect $ buildNodesGraph ns
          ids <- liftEffect $ Graph.nodeIds g
          sort ids `shouldEqual` sort (map _.id ns)

      it "layout is deterministic for the same input" do
        specs <- liftEffect $ randomSample' 20 (arbitrary :: Gen ArbGraphSpec)
        for_ specs \(ArbGraphSpec spec) -> do
          p1 <- liftEffect $ positionsOf spec
          p2 <- liftEffect $ positionsOf spec
          (p1 === p2) `shouldSatisfy` isSuccess

      it "layout positions are non-negative" do
        specs <- liftEffect $ randomSample' 30 (arbitrary :: Gen ArbGraphSpec)
        for_ specs \(ArbGraphSpec spec) -> do
          positions <- liftEffect $ positionsOf spec
          for_ positions \{ pos } -> do
            pos.x `shouldSatisfy` (_ >= 0.0)
            pos.y `shouldSatisfy` (_ >= 0.0)
