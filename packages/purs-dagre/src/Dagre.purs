-- | Low-level FFI bindings to the dagre JavaScript library (npm: dagre@0.8.5).
-- |
-- | dagre is a synchronous layout engine: you build a graph, call `layout`,
-- | and read back x/y coordinates for each node.
-- |
-- | This module exposes the opaque `ForeignGraph` type and raw FFI primitives.
-- | For an idiomatic API with algebraic data types, see `Dagre.Graph`.
-- |
-- | dagre is an npm peer-depency: consumers must `npm install dagre@0.8.5`.
module Dagre
  ( ForeignGraph
  , newGraph
  , setRankDir
  , setNodeImpl
  , setEdgeImpl
  , layoutImpl
  , nodeX
  , nodeY
  , nodes
  , graphWidth
  , graphHeight
  ) where

import Prelude

import Data.Nullable (Nullable)
import Effect (Effect)

-- | Opaque reference to a mutable dagre graphlib.Graph instance.
foreign import data ForeignGraph :: Type

-- | Create a new directed graph with default options.
-- | Internally calls `setGraph({})` and `setDefaultEdgeLabel(() => ({}))`.
foreign import newGraph :: Effect ForeignGraph

-- | Set the rank direction ("TB" | "BT" | "LR" | "RL").
foreign import setRankDir :: ForeignGraph -> String -> Effect Unit

-- | Add a node with the given id, dimensions, and label.
foreign import setNodeImpl
  :: ForeignGraph
  -> String
  -> { width :: Number, height :: Number }
  -> String
  -> Effect Unit

-- | Add a directed edge from source to target.
foreign import setEdgeImpl :: ForeignGraph -> String -> String -> Effect Unit

-- | Run the layout algorithm. Mutates the graph in place, populating x/y
-- | coordinates on every node.
foreign import layoutImpl :: ForeignGraph -> Effect Unit

-- | Read the x-coordinate of a node after layout. Returns null if the node
-- | does not exist or layout has not been run.
foreign import nodeX :: ForeignGraph -> String -> Effect (Nullable Number)

-- | Read the y-coordinate of a node after layout.
foreign import nodeY :: ForeignGraph -> String -> Effect (Nullable Number)

-- | List all node ids in the graph.
foreign import nodes :: ForeignGraph -> Effect (Array String)

-- | Total computed width of the laid-out graph.
foreign import graphWidth :: ForeignGraph -> Effect (Nullable Number)

-- | Total computed height of the laid-out graph.
foreign import graphHeight :: ForeignGraph -> Effect (Nullable Number)
