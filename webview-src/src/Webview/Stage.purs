-- | Pure logic of the fluent panel: everything about the stage that does not
-- | touch the DOM or the wasm engine. Kept pure so the layout, escaping, and
-- | drag-target selection are testable without a webview.
module Webview.Stage
  ( StagePoint
  , edgeIndicesFor
  , escapeHtml
  , fluentStageHtml
  , nearestNode
  ) where

import Prelude

import Data.Array (mapMaybe, mapWithIndex)
import Data.Foldable (foldl)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.String.Common as SC
import Data.String.Pattern (Pattern(..), Replacement(..))
import Data.Tuple (Tuple(..))
import GraphProtocol (FluentPayload)

-- | A node position in stage coordinates (viewBox: 900 x 520).
type StagePoint =
  { x :: Number
  , y :: Number
  }

-- | Resolve payload edge endpoints to node indices, dropping edges that
-- | reference unknown node ids.
edgeIndicesFor :: FluentPayload -> Array (Tuple Int Int)
edgeIndicesFor payload =
  let
    ids :: Map String Int
    ids = Map.fromFoldable (mapWithIndex (\i nd -> Tuple nd.id i) payload.nodes)
  in
    mapMaybe (\e -> Tuple <$> Map.lookup e.from ids <*> Map.lookup e.to ids) payload.edges

-- | The index of the node closest to (x, y) within `radius` stage units —
-- | the drag grab target. `Nothing` when no node is close enough.
nearestNode :: Array StagePoint -> Number -> Number -> Number -> Maybe Int
nearestNode nodes x y radius =
  let
    withinRadius d = d <= radius * radius

    closer (Tuple bestD bestI) (Tuple d i)
      | d < bestD && withinRadius d = Tuple d (Just i)
      | otherwise = Tuple bestD bestI

    distances = mapWithIndex (\i p -> Tuple (squaredDistance p.x p.y) i) nodes

    squaredDistance px py = (px - x) * (px - x) + (py - y) * (py - y)
  in
    case foldl closer (Tuple top Nothing) distances of
      Tuple _ (Just i) -> Just i
      _ -> Nothing

-- | The fluent stage: one SVG with dashed animated edges and glow-styled
-- | node groups; every frame only touches attributes (transform / line
-- | coordinates), never innerHTML.
fluentStageHtml :: FluentPayload -> Array (Tuple Int Int) -> String
fluentStageHtml payload edgeIndices =
  "<svg id=\"stage\" xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 900 520\" width=\"900\" height=\"520\">"
    <> SC.joinWith ""
      ( mapWithIndex
          ( \k _ ->
              "<line id=\"fluent-e-" <> show k <> "\" class=\"fluent-edge\" x1=\"450\" y1=\"260\" x2=\"450\" y2=\"260\"/>"
          )
          edgeIndices
      )
    <> SC.joinWith ""
      ( mapWithIndex
          ( \i nd ->
              "<g id=\"fluent-n-" <> show i <> "\" class=\"fluent-node-g\" transform=\"translate(450 260)\"><circle class=\"fluent-node\" r=\"16\"/><text class=\"fluent-label\" y=\"4\">"
                <> escapeHtml nd.label
                <> "</text></g>"
          )
          payload.nodes
      )
    <> "</svg>"

-- | Minimal HTML escaping for text injected via innerHTML.
escapeHtml :: String -> String
escapeHtml =
  SC.replaceAll (Pattern "'") (Replacement "&#39;")
    <<< SC.replaceAll (Pattern "\"") (Replacement "&quot;")
    <<< SC.replaceAll (Pattern ">") (Replacement "&gt;")
    <<< SC.replaceAll (Pattern "<") (Replacement "&lt;")
    <<< SC.replaceAll (Pattern "&") (Replacement "&amp;")
