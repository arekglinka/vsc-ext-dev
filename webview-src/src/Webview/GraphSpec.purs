-- | Decoder for the JSON graph spec accepted by `*.graph.json` preview files.
-- |
-- | Spec shape (all fields except `nodes[].id` / `edges[].from|to` optional):
-- | `{ "rankDir": "TB"|"BT"|"LR"|"RL", "nodes": [...], "edges": [...] }`.
module Webview.GraphSpec
  ( GraphSpec
  , NodeSpec
  , EdgeSpec
  , decodeSpec
  , rankDirFromString
  ) where

import Prelude

import Dagre.Graph (RankDir(..))
import Data.Argonaut.Core (Json)
import Data.Argonaut.Decode (decodeJson)
import Data.Argonaut.Decode.Error (JsonDecodeError, printJsonDecodeError)
import Data.Bifunctor (lmap)
import Data.Either (Either)
import Data.Maybe (Maybe(..), fromMaybe)

type NodeSpec =
  { id :: String
  , label :: String
  , width :: Number
  , height :: Number
  }

type EdgeSpec =
  { from :: String
  , to :: String
  }

type GraphSpec =
  { rankDir :: RankDir
  , nodes :: Array NodeSpec
  , edges :: Array EdgeSpec
  }

type RawSpec =
  { rankDir :: Maybe String
  , nodes :: Array RawNode
  , edges :: Array RawEdge
  }

type RawNode =
  { id :: String
  , label :: Maybe String
  , width :: Maybe Number
  , height :: Maybe Number
  }

type RawEdge =
  { from :: String
  , to :: String
  }

-- | Decode a graph spec, applying defaults: label `""`, size 120x60,
-- | rankDir `TopBottom` for missing or unknown `rankDir` values.
decodeSpec :: Json -> Either String GraphSpec
decodeSpec json = do
  raw <- lmap printJsonDecodeError (decodeJson json :: Either JsonDecodeError RawSpec)
  pure
    { rankDir: fromMaybe TopBottom (map rankDirFromString raw.rankDir)
    , nodes: map normalizeNode raw.nodes
    , edges: map (\e -> { from: e.from, to: e.to }) raw.edges
    }

normalizeNode :: RawNode -> NodeSpec
normalizeNode n =
  { id: n.id
  , label: fromMaybe "" n.label
  , width: fromMaybe 120.0 n.width
  , height: fromMaybe 60.0 n.height
  }

rankDirFromString :: String -> RankDir
rankDirFromString = case _ of
  "TB" -> TopBottom
  "BT" -> BottomTop
  "LR" -> LeftRight
  "RL" -> RightLeft
  _ -> TopBottom
