-- | VSCode webview API surface, kept deliberately thin (gallery mode adds
-- | click handlers on the nav buttons and the Open-in-editor button).
-- |
-- | `acquireVsCodeApi` may only be called once per webview page; `acquireApi`
-- | is called exactly once in `Webview.Main`. DOM reads/writes go through id
-- | lookups (`#status`, `#canvas`) so no web-html/web-dom dependency is needed.
module Webview.Ffi
  ( Api
  , acquireApi
  , nowMs
  , postMessage
  , onMessage
  , setHtmlById
  , setTextById
  , addClassById
  , removeClassById
  , onClickById
  , onFrame
  , onMouseMoveById
  , onMouseLeaveById
  , onDragStartById
  , onDragEnd
  , moveNodeById
  , setLineById
  ) where

import Prelude

import Effect (Effect)

-- | The object returned by VSCode's `acquireVsCodeApi()`.
foreign import data Api :: Type

foreign import acquireApi :: Effect Api

foreign import nowMs :: Effect Number

foreign import setHtmlById :: String -> String -> Effect Unit

foreign import postMessage :: forall msg. Api -> msg -> Effect Unit

foreign import onMessage :: forall msg. Api -> (msg -> Effect Unit) -> Effect Unit

foreign import setTextById :: String -> String -> Effect Unit

foreign import addClassById :: String -> String -> Effect Unit

foreign import removeClassById :: String -> String -> Effect Unit

-- | Attach a click handler to the element with the given id (no-op when the
-- | element is absent — same guard as the DOM writers above).
foreign import onClickById :: String -> Effect Unit -> Effect Unit

-- | Schedule an animation-frame callback (`requestAnimationFrame`; falls
-- back to a 16ms timeout where rAF is unavailable, e.g. headless harnesses).
foreign import onFrame :: Effect Unit -> Effect Unit

-- | Attach a mousemove handler receiving pointer coordinates relative to the
-- element plus the element's rendered width (viewBox↔CSS scale factor).
foreign import onMouseMoveById :: String -> (Number -> Number -> Number -> Effect Unit) -> Effect Unit

-- | Attach a mouseleave handler (`mouseleave` → e.g. drop the pointer well).
foreign import onMouseLeaveById :: String -> Effect Unit -> Effect Unit

-- | Attach a mousedown handler (drag start) with the same coordinate shape
-- as `onMouseMoveById`.
foreign import onDragStartById :: String -> (Number -> Number -> Number -> Effect Unit) -> Effect Unit

-- | Window-level mouseup (drag end — fires even outside the stage).
foreign import onDragEnd :: Effect Unit -> Effect Unit

-- | Move an SVG group to (x, y) via its `transform` attribute (fluent panel).
foreign import moveNodeById :: String -> Number -> Number -> Effect Unit

-- | Set the four coordinates of an SVG line (fluent panel edges).
foreign import setLineById :: String -> Number -> Number -> Number -> Number -> Effect Unit
