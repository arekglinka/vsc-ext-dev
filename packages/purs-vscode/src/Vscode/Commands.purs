-- | Bindings to `vscode.commands`: command registration.
-- |
-- | FFI note: the `.js` counterpart uses the DEFAULT import
-- | (`import vscode from "vscode"`) — under Node's CJS-ESM interop a
-- | namespace import does not surface the stub's members; see `Vscode.Core`.
module Vscode.Commands
  ( registerCommand
  ) where

import Prelude

import Effect (Effect)

import Vscode.Core (Disposable)

-- | Register a command (`vscode.commands.registerCommand id handler`),
-- | returning a `Disposable` that unregisters it. The host pushes it onto
-- | `context.subscriptions` (`extension.ts:145-148`).
-- |
-- | Handlers are nullary: an `Effect Unit` value IS a nullary JS thunk, so
-- | it is passed through the FFI untouched and invoked as
-- | `handler()` by the host. To accept command arguments later, widen this
-- | to `String -> (Foreign -> Effect Unit) -> Effect Disposable` — the JS
-- | layer needs no change (the vscode API already passes `(…args)` through),
-- | and existing registration call sites only edit the handler literal.
foreign import registerCommand :: String -> Effect Unit -> Effect Disposable
