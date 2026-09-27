-- | Bindings to `vscode.WebviewPanel` / `vscode.Webview`: the panel lifecycle
-- | (reveal, visibility guard, disposal) and the webview's HTML + message
-- | channel.
-- |
-- | FFI note: the `.js` counterpart uses the DEFAULT import
-- | (`import vscode from "vscode"`) — under Node's CJS-ESM interop a
-- | namespace import does not surface the stub's members; see `Vscode.Core`.
-- |
-- | The intentionally bound surface mirrors `src/extension.ts:82,96,99-116,
-- | 118,142,156` and nothing more — every panel/webview call site the host
-- | makes, with none of the speculative panel API.
-- |
-- | Deliberate deviation: `onDidReceiveMessage` is bound in its 2-arg form,
-- | returning the `Disposable` to the CALLER, instead of the real API's
-- | `(handler, thisArg, disposables)` form. The host (Task 11's `Host.Main`)
-- | pushes the returned disposable onto the context's subscriptions
-- | explicitly, which is behaviorally identical to the 3-arg form's internal
-- | push (same disposable, same array, same lifetime).
module Vscode.WebviewPanel
  ( panelReveal
  , panelVisible
  , panelOnDispose
  , webviewOf
  , setWebviewHtml
  , postMessage
  , asWebviewUri
  , onDidReceiveMessage
  ) where

import Prelude

import Data.Argonaut.Core (Json)
import Effect (Effect)
import Vscode.Core (Disposable, Uri, ViewColumn, Webview, WebviewPanel)

-- | Show the panel in the given column (`panel.reveal(column)`). The host
-- | feeds `viewColumn + 1` when the editor has a column, `beside` otherwise
-- | (`extension.ts:82`) — the numeric `ViewColumn` arithmetic happens in PS.
foreign import panelReveal :: WebviewPanel -> ViewColumn -> Effect Unit

-- | Whether the panel is currently visible (`panel.visible`) — the guard that
-- | suppresses redundant live refreshes while the panel is hidden
-- | (`extension.ts:118`). Do NOT lose this check in host ports.
foreign import panelVisible :: WebviewPanel -> Effect Boolean

-- | Subscribe to panel disposal (`panel.onDidDispose`). The host deletes its
-- | registry entry here (`extension.ts:114`); the returned `Disposable`
-- | unregisters the handler.
foreign import panelOnDispose :: WebviewPanel -> Effect Unit -> Effect Disposable

-- | The panel's webview (`panel.webview`) — handle for the HTML and message
-- | bindings below.
foreign import webviewOf :: WebviewPanel -> Effect Webview

-- | Set the webview's HTML document (`webview.html = …`). The host assigns
-- | exactly once per panel, `Host.Html.getHtml` output (`extension.ts:96`).
foreign import setWebviewHtml :: Webview -> String -> Effect Unit

-- | Post a message to the webview (`webview.postMessage(msg)`). Fire-and-forget
-- | `Effect Unit`: the returned Thenable is discarded — NO `.catch`, NO Aff
-- | wrapper — in parity with the host's `void panel.webview.postMessage(msg)`
-- | (`extension.ts:142`). The argonaut `Json` crosses the FFI AS the
-- | underlying JS value (argonaut 7.x represents `Json` as the raw value), so
-- | it must never be stringified or re-parsed on the way through.
foreign import postMessage :: Webview -> Json -> Effect Unit

-- | Rewrite a workspace Uri into one loadable inside the webview
-- | (`webview.asWebviewUri(uri)`) — used for the script src
-- | (`extension.ts:156`).
foreign import asWebviewUri :: Webview -> Uri -> Effect Uri

-- | Subscribe to webview→host messages
-- | (`webview.onDidReceiveMessage(handler)`). The raw JS payload arrives AS
-- | `Json` (same raw-value representation as `postMessage`) for protocol
-- | decoding. 2-arg form — see the module-header note on the deviation from
-- | the API's 3-arg subscription shape.
foreign import onDidReceiveMessage :: Webview -> (Json -> Effect Unit) -> Effect Disposable
