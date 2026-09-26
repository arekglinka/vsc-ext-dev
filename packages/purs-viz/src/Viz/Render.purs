-- | Idiomatic rendering API for viz.js.
-- |
-- | Wraps the raw FFI in `Viz` with an algebraic data type for results and
-- | `Either` for error handling — no exceptions cross the FFI boundary.
module Viz.Render
  ( renderString
  , renderJSON
  , renderSVG
  , Engine(..)
  , engineToString
  , RenderError
  , RenderOptions
  , defaultRenderOptions
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Nullable (toMaybe)
import Viz (RenderResultRaw, VizInstance, renderRaw)

-- | Graphviz layout engine.
data Engine
  = Dot
  | Neato
  | Circo
  | Fdp
  | Twopi

engineToString :: Engine -> String
engineToString = case _ of
  Dot -> "dot"
  Neato -> "neato"
  Circo -> "circo"
  Fdp -> "fdp"
  Twopi -> "twopi"

-- | A render error message (viz.js reports errors as strings).
type RenderError = String

-- | Options for a render call. `format` controls output ("svg", "json",
-- | "dot", "plain"); `engine` selects the layout algorithm.
type RenderOptions =
  { format :: String
  , engine :: Engine
  }

defaultRenderOptions :: RenderOptions
defaultRenderOptions = { format: "svg", engine: Dot }

-- | Render DOT source to an SVG string. Returns `Left errors` on failure
-- | (e.g. invalid DOT syntax).
renderString :: VizInstance -> String -> Maybe RenderOptions -> Either (Array RenderError) String
renderString viz input opts =
  toEither result
  where
  o = fromMaybe defaultRenderOptions opts
  result = renderRaw viz { input, format: o.format, engine: engineToString o.engine }

-- | Render DOT source to a JSON string (Graphviz JSON output format).
-- | The consumer can `JSON.parse` the result if a structured object is needed.
renderJSON :: VizInstance -> String -> Maybe Engine -> Either (Array RenderError) String
renderJSON viz input engine =
  toEither result
  where
  e = fromMaybe Dot engine
  result = renderRaw viz { input, format: "json", engine: engineToString e }

-- | Convenience: render DOT directly to SVG with just an engine selection.
renderSVG :: VizInstance -> String -> Maybe Engine -> Either (Array RenderError) String
renderSVG viz input engine =
  toEither result
  where
  e = fromMaybe Dot engine
  result = renderRaw viz { input, format: "svg", engine: engineToString e }

toEither :: RenderResultRaw -> Either (Array RenderError) String
toEither result =
  if result.status == "success" then case toMaybe result.output of
    Just output -> Right output
    Nothing -> Left [ "render succeeded but produced no output" ]
  else Left (map _.message result.errors)
