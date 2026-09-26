-- | VSCode webview API surface, kept deliberately thin.
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
