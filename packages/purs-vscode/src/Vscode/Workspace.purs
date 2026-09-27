-- | Bindings to `vscode.workspace`: configuration reads, the text-document
-- | change event behind live refresh, and untitled-document creation for the
-- | showcase gallery's "Open sample in editor" action.
-- |
-- | FFI note: the `.js` counterpart uses the DEFAULT import
-- | (`import vscode from "vscode"`) — under Node's CJS-ESM interop a
-- | namespace import does not surface the stub's members; see `Vscode.Core`.
-- |
-- | The intentionally bound surface mirrors `src/extension.ts:117-125` and
-- | `:140` — the single `getConfiguration("pursGraphs").get` config read and
-- | the `onDidChangeTextDocument` subscription whose event flows
-- | `eventDocument` → `documentUri` → `uriToString` at the call site — plus
-- | `openTextDocumentWithContent` for the showcase gallery (post-migration
-- | feature work, not part of the frozen port).
module Vscode.Workspace
  ( getConfiguration
  , getConfigString
  , onDidChangeTextDocument
  , eventDocument
  , openTextDocumentWithContent
  ) where

import Prelude

import Effect (Effect)
import Vscode.Core (Configuration, Disposable, TextDocument, TextDocumentChangeEvent)

-- | Open a configuration section (`vscode.workspace.getConfiguration`).
-- | Not cached: read per use, matching the host's per-push config lookup
-- | (`extension.ts:140`).
foreign import getConfiguration :: String -> Effect Configuration

-- | Read a string value with a fallback
-- | (`config.get(key, defaultValue)`) — the default is returned when the
-- | key is unset, exactly like the host's `get("dotEngine", "dot")`.
foreign import getConfigString :: Configuration -> String -> String -> Effect String

-- | Subscribe to document changes
-- | (`vscode.workspace.onDidChangeTextDocument`). The returned `Disposable`
-- | unregisters the handler; the host pushes it onto the context's
-- | subscriptions (`extension.ts:125`).
foreign import onDidChangeTextDocument
  :: (TextDocumentChangeEvent -> Effect Unit) -> Effect Disposable

-- | The document the change event is about (`event.document`) — the first hop
-- | of the host's `event.document.uri.toString()` key match
-- | (`extension.ts:118`, `:121`).
foreign import eventDocument :: TextDocumentChangeEvent -> Effect TextDocument

-- | Open an untitled text document with the given language id and content
-- | (`vscode.workspace.openTextDocument({ language, content })`). Like the
-- | sibling bindings this is stub-synchronous: the dev-only stub returns the
-- | document immediately; the real API returns a Thenable (the same
-- | convention `createWebviewPanel` already follows — see `Vscode.Window`).
foreign import openTextDocumentWithContent :: String -> String -> Effect TextDocument
