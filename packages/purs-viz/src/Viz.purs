-- | Low-level FFI bindings to @viz-js/viz (npm: @viz-js/viz 3.x).
-- |
-- | viz.js provides full Graphviz rendering (DOT → SVG/JSON/etc.) via a
-- | WebAssembly build of Graphviz. Instance creation is asynchronous (WASM
-- | instantiation); rendering is synchronous.
-- |
-- | This module exposes the opaque `VizInstance` type and the async `new`
-- | operation. For idiomatic rendering helpers, see `Viz.Render`.
-- |
-- | @viz-js/viz is an npm peer-dependency: consumers must install it.
module Viz
  ( VizInstance
  , new
  , renderRaw
  , RenderResultRaw
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Function.Uncurried (Fn4, runFn4)
import Data.Nullable (Nullable)
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Exception (error)

-- | An initialised viz.js instance (WASM module loaded, ready to render).
foreign import data VizInstance :: Type

-- | Raw result shape from `viz.render()` — status is "success" or "failure".
type RenderResultRaw =
  { status :: String
  , output :: Nullable String
  , errors :: Array { message :: String }
  }

-- | Internal: start async instance creation, calling callbacks on completion.
foreign import _startInstance
  :: (VizInstance -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit

-- | Internal: synchronous render with format + engine options. Never throws.
foreign import _render :: Fn4 VizInstance String String String RenderResultRaw

-- | Create a new VizInstance. This loads the WebAssembly Graphviz module,
-- | so it runs in `Aff` (instance creation is async).
new :: Aff VizInstance
new = makeAff \k -> do
  _startInstance
    (\viz -> k (Right viz))
    (\msg -> k (Left (error msg)))
  pure nonCanceler

-- | Low-level synchronous render. Returns the raw result object from viz.js.
-- | For an idiomatic `Either`-returning API, use `Viz.Render.renderString`.
renderRaw
  :: VizInstance -> { input :: String, format :: String, engine :: String } -> RenderResultRaw
renderRaw viz opts = runFn4 _render viz opts.input opts.format opts.engine
