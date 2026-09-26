-- | Idiomatic PureScript API for dagre graph layout.
-- |
-- | Wraps the raw FFI in `Dagre` with algebraic data types and `Maybe` for
-- | nullable results.
module Dagre.Graph
  ( Graph(..)
  , RankDir(..)
  , rankDirToString
  , NodeOptions
  , Position
  , new
  , setRankDir
  , setNode
  , setEdge
  , layout
  , nodePosition
  , nodeIds
  , dimensions
  ) where

import Prelude

import Dagre
  ( ForeignGraph
  , graphHeight
  , graphWidth
  , layoutImpl
  , newGraph
  , nodeX
  , nodeY
  , nodes
  , setEdgeImpl
  , setNodeImpl
  , setRankDir
  ) as Dagre
import Data.Maybe (Maybe(..))
import Data.Nullable (toMaybe)
import Effect (Effect)

-- | A mutable dagre graph. The underlying foreign object is shared by
-- | reference, so operations mutate it in place.
newtype Graph = Graph Dagre.ForeignGraph

-- | Rank direction for the layered layout algorithm.
data RankDir
  = TopBottom
  | BottomTop
  | LeftRight
  | RightLeft

rankDirToString :: RankDir -> String
rankDirToString = case _ of
  TopBottom -> "TB"
  BottomTop -> "BT"
  LeftRight -> "LR"
  RightLeft -> "RL"

-- | Options for placing a node.
type NodeOptions =
  { id :: String
  , width :: Number
  , height :: Number
  , label :: String
  }

-- | A 2D position computed by the layout algorithm.
type Position =
  { x :: Number
  , y :: Number
  }

-- | Create a new empty directed graph.
new :: Effect Graph
new = Graph <$> Dagre.newGraph

-- | Set the rank direction. Call before `layout`.
setRankDir :: RankDir -> Graph -> Effect Unit
setRankDir dir (Graph g) = Dagre.setRankDir g (rankDirToString dir)

-- | Add or update a node with the given options.
setNode :: NodeOptions -> Graph -> Effect Unit
setNode opts (Graph g) =
  Dagre.setNodeImpl g opts.id { width: opts.width, height: opts.height } opts.label

-- | Add a directed edge from source to target.
setEdge :: { source :: String, target :: String } -> Graph -> Effect Unit
setEdge opts (Graph g) = Dagre.setEdgeImpl g opts.source opts.target

-- | Run the layout algorithm. After this call, node positions are available
-- | via `nodePosition`.
layout :: Graph -> Effect Unit
layout (Graph g) = Dagre.layoutImpl g

-- | Read the computed position of a node. Returns `Nothing` if the node does
-- | not exist or `layout` has not been run.
nodePosition :: String -> Graph -> Effect (Maybe Position)
nodePosition id (Graph g) = do
  mx <- toMaybe <$> Dagre.nodeX g id
  my <- toMaybe <$> Dagre.nodeY g id
  pure case mx, my of
    Just x, Just y -> Just { x, y }
    _, _ -> Nothing

-- | List all node ids in the graph.
nodeIds :: Graph -> Effect (Array String)
nodeIds (Graph g) = Dagre.nodes g

-- | Total computed width and height of the laid-out graph.
dimensions :: Graph -> Effect (Maybe { width :: Number, height :: Number })
dimensions (Graph g) = do
  mw <- toMaybe <$> Dagre.graphWidth g
  mh <- toMaybe <$> Dagre.graphHeight g
  pure case mw, mh of
    Just w, Just h -> Just { width: w, height: h }
    _, _ -> Nothing
