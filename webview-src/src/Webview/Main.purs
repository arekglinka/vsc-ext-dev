-- | Webview entry point.
-- |
-- | Wires the host message protocol to the two renderers. The viz instance
-- | is created asynchronously (WASM), so messages arriving before it is ready
-- | are buffered in a `Ref` and rendered on completion; later messages
-- | re-render immediately.
module Webview.Main
  ( main
  ) where

import Prelude

import Data.Array (intercalate)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import Viz as Viz
import Webview.Ffi
  ( acquireApi
  , addClassById
  , nowMs
  , onMessage
  , postMessage
  , removeClassById
  , setHtmlById
  , setTextById
  )
import Webview.Render (renderDot, renderGraph)

type HostUpdate =
  { kind :: String
  , source :: String
  , engine :: String
  }

main :: Effect Unit
main = do
  api <- acquireApi
  pending <- Ref.new Nothing
  vizRef <- Ref.new Nothing

  let
    setStatus msg isError = do
      setTextById "status" msg
      if isError then addClassById "status" "error" else removeClassById "status" "error"

    renderWhenReady = do
      mviz <- Ref.read vizRef
      mupd <- Ref.read pending
      case mviz, mupd of
        Just viz, Just upd -> do
          Ref.write Nothing pending
          t0 <- nowMs
          result <- case upd.kind of
            "dot" -> pure $ renderDot viz upd.source upd.engine
            _ -> renderGraph upd.source
          t1 <- nowMs
          let ms = t1 - t0
          case result of
            Right svg -> do
              setHtmlById "canvas" svg
              setStatus (upd.kind <> " • rendered in " <> show ms <> "ms") false
              postMessage api { type: "rendered", kind: upd.kind, ms }
            Left errs -> do
              let msg = intercalate "; " errs
              setStatus msg true
              postMessage api { type: "error", kind: upd.kind, message: msg }
        _, _ -> pure unit

  onMessage api \upd -> do
    Ref.write (Just upd) pending
    renderWhenReady

  launchAff_ do
    viz <- Viz.new
    liftEffect do
      Ref.write (Just viz) vizRef
      postMessage api { type: "ready" }
      renderWhenReady
