-- | PureScript surface over the Rust/WASM force-simulation engine
-- | (`fluent-wasm` crate, inlined into the bundle as base64). The JS side is
-- | a thin bridge that instantiates the module and hands back the raw wasm
-- | exports; everything else — instance caching, error handling, the typed
-- | API — lives here.
module Webview.Fluent
  ( Engine
  , withEngine
  , engineConfigure
  , engineSetEdge
  , engineSetMouse
  , engineGrab
  , engineRelease
  , engineStep
  , engineX
  , engineY
  ) where

import Prelude

import Data.Function.Uncurried (Fn2, Fn3, runFn2, runFn3)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Webview.Ffi (addClassById, setTextById)

-- | Raw wasm exports, shaped by the FFI bridge. `readX`/`readY` are
-- | `Effect`-ful on purpose: they read mutable linear memory, so a pure
-- | signature would let the backend hoist reads out of the frame loop.
type Engine =
  { configure :: Fn2 Int Int (Effect Unit)
  , setEdge :: Fn3 Int Int Int (Effect Unit)
  , setMouse :: Fn3 Number Number Boolean (Effect Unit)
  , grab :: Int -> Effect Unit
  , release :: Effect Unit
  , step :: Number -> Effect Unit
  , readX :: Int -> Effect Number
  , readY :: Int -> Effect Number
  }

-- | Start asynchronous wasm instantiation, reporting the ready engine or an
-- | error message through the callbacks (same bridge shape as purs-viz).
foreign import _startEngine
  :: (Engine -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit

-- | Run the callback with the engine, instantiating it at most once per
-- | `cache` ref. A failed instantiation surfaces on the status line and the
-- | callback is skipped.
withEngine :: Ref (Maybe Engine) -> (Engine -> Effect Unit) -> Effect Unit
withEngine cache run = do
  cached <- Ref.read cache
  case cached of
    Just engine -> run engine
    Nothing ->
      _startEngine
        ( \engine -> do
            Ref.write (Just engine) cache
            run engine
        )
        ( \message -> do
            setTextById "status" ("engine failed: " <> message)
            addClassById "status" "error"
        )

engineConfigure :: Engine -> Int -> Int -> Effect Unit
engineConfigure engine nodes edges = runFn2 engine.configure nodes edges

engineSetEdge :: Engine -> Int -> Int -> Int -> Effect Unit
engineSetEdge engine k a b = runFn3 engine.setEdge k a b

engineSetMouse :: Engine -> Number -> Number -> Boolean -> Effect Unit
engineSetMouse engine x y active = runFn3 engine.setMouse x y active

engineGrab :: Engine -> Int -> Effect Unit
engineGrab engine = engine.grab

engineRelease :: Engine -> Effect Unit
engineRelease engine = engine.release

engineStep :: Engine -> Number -> Effect Unit
engineStep engine = engine.step

engineX :: Engine -> Int -> Effect Number
engineX engine = engine.readX

engineY :: Engine -> Int -> Effect Number
engineY engine = engine.readY
