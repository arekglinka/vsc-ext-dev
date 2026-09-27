-- | Webview entry point.
-- |
-- | Wires the host message protocol to the two renderers, in two modes:
-- |
-- |   * preview mode — the classic `update` messages: each message replaces
-- |     the canvas with the rendered graph (live refresh).
-- |   * gallery mode — `showcase` messages: build the sample nav, render
-- |     the selected sample into the canvas, and post `OpenSample` when the
-- |     "Open sample in editor" button is clicked.
-- |   * fluent mode — `fluentPanel` messages: build the stage SVG once, then
-- |     run a requestAnimationFrame loop that steps the Rust/WASM force
-- |     simulation (`Webview.Fluent`) and syncs node/edge DOM positions every
-- |     frame. A generation token cancels the previous loop when a fresh
-- |     payload arrives (panel re-reveal).
-- |
-- | The viz instance is created asynchronously (WASM), so messages arriving
-- | before it is ready are buffered in `Ref`s and rendered on completion;
-- | later messages re-render immediately. Gallery state persists after the
-- | nav is built (nav clicks re-render directly — viz is ready by then), and
-- | a fresh `showcase` message rebuilds the nav from scratch.
-- |
-- | All message shapes come from the shared `GraphProtocol` codecs: outbound
-- | messages are encoded with `encodeWebviewToHost` (argonaut `Json` is the
-- | raw JS value, so it crosses the `postMessage` FFI unchanged), and inbound
-- | payloads are decoded strictly with `decodeHostUpdate` / `decodeShowcase` —
-- | malformed or unrecognized messages are ignored silently.
module Webview.Main
  ( main
  ) where

import Prelude

import Data.Array (index, intercalate, length, mapWithIndex, (..))
import Data.Either (Either(..))
import Data.Foldable (sequence_)
import Data.Maybe (Maybe(..))
import Data.String.Pattern (Pattern(..), Replacement(..))
import Data.Traversable (traverse)
import Data.Tuple (Tuple(..))
import Data.String.Common as SC
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import GraphProtocol
  ( FluentPayload
  , GraphKind(..)
  , WebviewToHost(..)
  , decodeFluentPanel
  , decodeHostUpdate
  , decodeShowcase
  , encodeWebviewToHost
  , kindToString
  )
import Viz as Viz
import Webview.Ffi
  ( acquireApi
  , addClassById
  , moveNodeById
  , nowMs
  , onClickById
  , onDragEnd
  , onDragStartById
  , onFrame
  , onMessage
  , onMouseLeaveById
  , onMouseMoveById
  , postMessage
  , removeClassById
  , setHtmlById
  , setLineById
  , setTextById
  )
import Webview.Fluent
  ( Engine
  , engineConfigure
  , engineGrab
  , engineRelease
  , engineSetEdge
  , engineSetMouse
  , engineStep
  , engineX
  , engineY
  , withEngine
  )
import Webview.Render (renderDot, renderGraph)
import Webview.Stage (StagePoint, edgeIndicesFor, escapeHtml, fluentStageHtml, nearestNode)

-- | What the shared renderer needs — everything a preview update or a
-- | gallery sample carries, plus the status-line prefix (`Nothing` keeps
-- | the preview status line byte-identical to the pre-gallery format).
type RenderRequest =
  { kind :: GraphKind
  , source :: String
  , engine :: String
  , label :: Maybe String
  }

main :: Effect Unit
main = do
  api <- acquireApi
  pending <- Ref.new Nothing
  gallery <- Ref.new Nothing
  selected <- Ref.new 0
  vizRef <- Ref.new Nothing
  fluentGen <- Ref.new 0
  frameCounter <- Ref.new 0
  engineCache <- Ref.new Nothing

  let
    setStatus msg isError = do
      setTextById "status" msg
      if isError then addClassById "status" "error" else removeClassById "status" "error"

    renderToCanvas viz req = do
      t0 <- nowMs
      result <- case req.kind of
        Dot -> pure $ renderDot viz req.source req.engine
        Graph -> renderGraph req.source
      t1 <- nowMs
      let
        ms = t1 - t0
        base = kindToString req.kind <> " • rendered in " <> show ms <> "ms"
        statusLine = case req.label of
          Just label -> label <> " • " <> base
          Nothing -> base
      case result of
        Right svg -> do
          setHtmlById "canvas" svg
          setStatus statusLine false
          postMessage api (encodeWebviewToHost (Rendered req.kind ms))
        Left errs -> do
          let msg = intercalate "; " errs
          setStatus msg true
          postMessage api (encodeWebviewToHost (WError req.kind msg))

    renderWhenReady = do
      mviz <- Ref.read vizRef
      mupd <- Ref.read pending
      case mviz, mupd of
        Just viz, Just upd -> do
          Ref.write Nothing pending
          renderToCanvas viz { kind: upd.kind, source: upd.source, engine: upd.engine, label: Nothing }
        _, _ -> pure unit

    navId i = "pg-nav-" <> show i

    sampleRequest s = { kind: s.kind, source: s.source, engine: s.engine, label: Just s.title }

    selectSample viz samples i = do
      prev <- Ref.read selected
      removeClassById (navId prev) "active"
      Ref.write i selected
      addClassById (navId i) "active"
      case index samples i of
        Just s -> do
          setTextById "desc" s.description
          renderToCanvas viz (sampleRequest s)
        Nothing -> pure unit

    navButtonHtml i s =
      "<button id=\"" <> navId i <> "\"><span class=\"pg-nav-title\">"
        <> escapeHtml s.title
        <> "</span><span class=\"pg-nav-meta\">"
        <> kindToString s.kind
        <> (if s.kind == Dot then " • " <> s.engine else "")
        <> "</span></button>"

    renderGalleryWhenReady = do
      mviz <- Ref.read vizRef
      mg <- Ref.read gallery
      case mviz, mg of
        Just viz, Just payload -> do
          Ref.write Nothing gallery
          setHtmlById "nav" (SC.joinWith "" (mapWithIndex navButtonHtml payload.samples))
          sequence_ (mapWithIndex (\i _ -> onClickById (navId i) (selectSample viz payload.samples i)) payload.samples)
          onClickById "open-editor" do
            sel <- Ref.read selected
            case index payload.samples sel of
              Just s -> postMessage api (encodeWebviewToHost (OpenSample s.id))
              Nothing -> pure unit
          case index payload.samples 0 of
            Just _ -> selectSample viz payload.samples 0
            Nothing -> setStatus "no samples in this gallery" true
        _, _ -> pure unit

    -- Fluent panel: build the stage once, then animate forever. Stage space
    -- is 900x520; pointer CSS coordinates are rescaled by rectW (the viewBox
    -- scale). A fresh payload bumps the generation token, which stops the
    -- previous frame loop instead of stacking a second one.
    startFluent payload = withEngine engineCache \engine -> do
      let
        edgeIndices = edgeIndicesFor payload
        n = length payload.nodes
      engineConfigure engine n (length edgeIndices)
      sequence_ (mapWithIndex (\k (Tuple a b) -> engineSetEdge engine k a b) edgeIndices)
      setHtmlById "canvas" (fluentStageHtml payload edgeIndices)
      onMouseMoveById "stage" \x y rectW -> do
        let scale = 900.0 / rectW
        engineSetMouse engine (x * scale) (y * scale) true
      onMouseLeaveById "stage" (engineSetMouse engine 0.0 0.0 false)
      -- Drag: press near a node (within 2.25x its radius) → the engine pins
      -- it to the pointer; release anywhere → springs pull the graph back.
      onDragStartById "stage" \x y rectW -> do
        let
          scale = 900.0 / rectW
          sx = x * scale
          sy = y * scale
        positions <- traverse (nodePosition engine) (0 .. (n - 1))
        case nearestNode positions sx sy 36.0 of
          Just i -> do
            engineSetMouse engine sx sy true
            engineGrab engine i
          Nothing -> pure unit
      onDragEnd (engineRelease engine)
      Ref.write 0 frameCounter
      gen <- Ref.modify (_ + 1) fluentGen
      let
        syncDom = do
          sequence_
            ( mapWithIndex
                ( \i _ -> do
                    x <- engineX engine i
                    y <- engineY engine i
                    moveNodeById ("fluent-n-" <> show i) x y
                )
                payload.nodes
            )
          sequence_
            ( mapWithIndex
                ( \k (Tuple a b) -> do
                    x1 <- engineX engine a
                    y1 <- engineY engine a
                    x2 <- engineX engine b
                    y2 <- engineY engine b
                    setLineById ("fluent-e-" <> show k) x1 y1 x2 y2
                )
                edgeIndices
            )
        loop = do
          engineStep engine 0.016
          syncDom
          count <- Ref.modify (_ + 1) frameCounter
          when (count `mod` 60 == 0) do
            setTextById "status" ("fluent • frame " <> show count <> " • " <> show n <> " nodes • Rust→WASM")
            removeClassById "status" "error"
          cur <- Ref.read fluentGen
          when (cur == gen) (onFrame loop)
      setTextById "status" ("fluent • warming up (" <> show n <> " nodes)")
      onFrame loop

  onMessage api \json -> case decodeHostUpdate json of
    Just upd -> do
      Ref.write (Just upd) pending
      renderWhenReady
    Nothing -> case decodeShowcase json of
      Just payload -> do
        Ref.write (Just payload) gallery
        renderGalleryWhenReady
      Nothing -> case decodeFluentPanel json of
        Just payload -> startFluent payload
        Nothing -> pure unit

  launchAff_ do
    viz <- Viz.new
    liftEffect do
      Ref.write (Just viz) vizRef
      postMessage api (encodeWebviewToHost Ready)
      renderWhenReady
      renderGalleryWhenReady

-- | Live position of node `i` in stage coordinates (read from wasm memory;
-- Effect-ful so the frame loop cannot cache stale values).
nodePosition :: Engine -> Int -> Effect StagePoint
nodePosition engine i = do
  x <- engineX engine i
  y <- engineY engine i
  pure { x, y }
