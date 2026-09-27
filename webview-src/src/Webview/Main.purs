-- | Webview entry point.
-- |
-- | Wires the host message protocol to the two renderers. The viz instance
-- | is created asynchronously (WASM), so messages arriving before it is ready
-- | are buffered in a `Ref` and rendered on completion; later messages
-- | re-render immediately.
-- |
-- | All message shapes come from the shared `GraphProtocol` codecs: outbound
-- | messages are encoded with `encodeWebviewToHost` (argonaut `Json` is the
-- | raw JS value, so it crosses the `postMessage` FFI unchanged), and inbound
-- | payloads are decoded strictly with `decodeHostUpdate` — malformed or
-- | unrecognized messages are ignored silently (the old code trusted the
-- | record shape; real messages are always well-formed, so the wire behavior
-- | is unchanged).
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
import GraphProtocol (GraphKind(..), WebviewToHost(..), decodeHostUpdate, encodeWebviewToHost, kindToString)
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
            Dot -> pure $ renderDot viz upd.source upd.engine
            Graph -> renderGraph upd.source
          t1 <- nowMs
          let ms = t1 - t0
          case result of
            Right svg -> do
              setHtmlById "canvas" svg
              setStatus (kindToString upd.kind <> " • rendered in " <> show ms <> "ms") false
              postMessage api (encodeWebviewToHost (Rendered upd.kind ms))
            Left errs -> do
              let msg = intercalate "; " errs
              setStatus msg true
              postMessage api (encodeWebviewToHost (WError upd.kind msg))
        _, _ -> pure unit

  onMessage api \json -> case decodeHostUpdate json of
    Just upd -> do
      Ref.write (Just upd) pending
      renderWhenReady
    Nothing -> pure unit

  launchAff_ do
    viz <- Viz.new
    liftEffect do
      Ref.write (Just viz) vizRef
      postMessage api (encodeWebviewToHost Ready)
      renderWhenReady
