-- | Bindings to `vscode.window`: the active text editor, error
-- | notifications, webview panel creation, and showing a document in an
-- | editor (the showcase gallery's "Open sample in editor" hop), plus the
-- | text-editor / text-document accessors (kept here to keep `Vscode.Window`
-- | cohesive — the opaque handles themselves live in `Vscode.Core`).
-- |
-- | FFI note: the `.js` counterpart uses the DEFAULT import
-- | (`import vscode from "vscode"`) — under Node's CJS-ESM interop a
-- | namespace import does not surface the stub's members; see `Vscode.Core`.
-- |
-- | The intentionally bound surface mirrors `src/extension.ts:66-95` and
-- | nothing more: `activeTextEditor` (with `?.document` / `.viewColumn`
-- | consumption), `showErrorMessage` (two exact call sites), and
-- | `createWebviewPanel` (the one call, `extension.ts:87-95`).
module Vscode.Window
  ( PanelOptions
  , activeTextEditor
  , showErrorMessage
  , createWebviewPanel
  , showTextDocument
  , editorDocument
  , editorViewColumn
  , documentFileName
  , documentLanguageId
  , documentUri
  , documentText
  ) where

import Prelude

import Data.Maybe (Maybe)
import Data.Nullable (Nullable, toMaybe)
import Effect (Effect)
import Vscode.Core (TextDocument, TextEditor, Uri, ViewColumn, WebviewPanel)

-- | Options for `createWebviewPanel`, passed to the FFI AS-IS — a PureScript
-- | record IS a plain JavaScript object, so the field names below are the
-- | wire contract with the vscode API and must never be normalized or
-- | copied in the JS layer.
type PanelOptions =
  { enableScripts :: Boolean
  , localResourceRoots :: Array Uri
  }

-- | Internal: `vscode.window.activeTextEditor` is `undefined` when no editor
-- | is active, hence the `Nullable` crossing.
foreign import _activeTextEditorImpl :: Effect (Nullable TextEditor)

-- | Show a text document in an editor
-- | (`vscode.window.showTextDocument(document)`). Stub-synchronous like
-- | `createWebviewPanel`: the returned Thenable is discarded and the stub
-- | records the call while activating an editor for the document.
foreign import showTextDocument :: TextDocument -> Effect Unit

-- | The currently active editor, or `Nothing` when no editor has focus
-- | (`vscode.window.activeTextEditor`).
activeTextEditor :: Effect (Maybe TextEditor)
activeTextEditor = toMaybe <$> _activeTextEditorImpl

-- | Show an error notification
-- | (`vscode.window.showErrorMessage`). Fire-and-forget: the returned
-- | promise is discarded, matching the host's un-awaited calls
-- | (`extension.ts:68`, `:73`); the stub always resolves.
foreign import showErrorMessage :: String -> Effect Unit

-- | Create a webview panel
-- | (`vscode.window.createWebviewPanel viewType title showOptions options`).
-- | The current host always passes `beside` as the show column
-- | (`extension.ts:90`); the `viewColumn + 1` arithmetic lives only in
-- | `reveal`, so this binding accepts any `ViewColumn` and lets the host
-- | layer decide.
foreign import createWebviewPanel
  :: String -> String -> ViewColumn -> PanelOptions -> Effect WebviewPanel

-- | The editor's open document (`editor.document`).
foreign import editorDocument :: TextEditor -> Effect TextDocument

-- | Internal: `editor.viewColumn` is `undefined` for editors not shown in a
-- | column (e.g. in a diff editor's original side), hence the `Nullable`.
foreign import _editorViewColumnImpl :: TextEditor -> Effect (Nullable ViewColumn)

-- | The column the editor is shown in, or `Nothing` when it has no column
-- | (`editor.viewColumn`; the host feeds `viewColumn + 1` arithmetic with
-- | `extension.ts:82`).
editorViewColumn :: TextEditor -> Effect (Maybe ViewColumn)
editorViewColumn editor = toMaybe <$> _editorViewColumnImpl editor

-- | The document's full file name (`document.fileName`). The host splits on
-- | `/` without Windows handling — parity preserved at the call site.
foreign import documentFileName :: TextDocument -> Effect String

-- | The document's language identifier (`document.languageId`).
foreign import documentLanguageId :: TextDocument -> Effect String

-- | The document's Uri (`document.uri`) — its string form
-- | (`uriToString`) is the panel map key (`extension.ts:81`).
foreign import documentUri :: TextDocument -> Effect Uri

-- | The document's full source text (`document.getText()`).
foreign import documentText :: TextDocument -> Effect String
