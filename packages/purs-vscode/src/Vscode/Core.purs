-- | Foundational bindings to the VSCode extension API: the opaque handles for
-- | the API's object types, `ViewColumn`, `Disposable` management, and the
-- | `Uri` / `ExtensionContext` primitives shared by every sibling module.
-- |
-- | All object types are opaque: values obtained from one binding flow through
-- | PureScript untouched and are only ever inspected by the FFI layer. Later
-- | modules (`Vscode.Window`, `Vscode.Commands`, `Vscode.Workspace`,
-- | `Vscode.WebviewPanel`) are the named accessors over these handles.
-- |
-- | FFI note: the `.js` counterpart uses the DEFAULT import
-- | (`import vscode from "vscode"`) — under Node's CJS-ESM interop a namespace
-- | import does not surface the stub's members; see `Vscode.Version`.
module Vscode.Core
  ( ExtensionContext
  , Disposable
  , Uri
  , TextDocument
  , TextEditor
  , WebviewPanel
  , Webview
  , Configuration
  , TextDocumentChangeEvent
  , ViewColumn(..)
  , unViewColumn
  , beside
  , viewColumnOne
  , viewColumnTwo
  , viewColumnThree
  , pushSubscription
  , dispose
  , extensionUri
  , joinPath
  , uriToString
  ) where

import Prelude

import Effect (Effect)

-- | Opaque handle to the extension's activation context
-- | (`vscode.ExtensionContext`): carries the extension install `Uri` and the
-- | `subscriptions` array that owns every disposable created during activation.
foreign import data ExtensionContext :: Type

-- | Opaque handle to a VSCode disposable (`{ dispose: () => void }`): the
-- | cancellation token for registrations (commands, events) and resources
-- | (panels). Produced by registration APIs; released via `dispose` or by
-- | pushing it onto the context with `pushSubscription`.
foreign import data Disposable :: Type

-- | Opaque handle to a VSCode `Uri`. The stub's URIs expose only `toString`;
-- | treat the string form (`uriToString`) as the only observation point.
foreign import data Uri :: Type

-- | Opaque handle to a text document (`vscode.TextDocument`): file name,
-- | language id, `Uri`, and source text. Accessors live in `Vscode.Window`.
foreign import data TextDocument :: Type

-- | Opaque handle to an active editor (`vscode.TextEditor`): pairs a
-- | `TextDocument` with its `ViewColumn`. Accessors live in `Vscode.Window`.
foreign import data TextEditor :: Type

-- | Opaque handle to a webview panel (`vscode.WebviewPanel`). Bound in
-- | `Vscode.WebviewPanel`.
foreign import data WebviewPanel :: Type

-- | Opaque handle to a panel's webview (`vscode.Webview`): the HTML document
-- | and its message channel. Bound in `Vscode.WebviewPanel`.
foreign import data Webview :: Type

-- | Opaque handle to a configuration section
-- | (`vscode.WorkspaceConfiguration`). Bound in `Vscode.Workspace`.
foreign import data Configuration :: Type

-- | Opaque handle to a document-change event payload
-- | (`vscode.TextDocumentChangeEvent`). Bound in `Vscode.Workspace`.
foreign import data TextDocumentChangeEvent :: Type

-- | Editor column position (`vscode.ViewColumn`), carried as its numeric
-- | value: VSCode's API computes reveal positions arithmetically
-- | (`viewColumn + 1`, falling back to `Beside`), so the numeric nature is
-- | load-bearing, not incidental.
newtype ViewColumn = ViewColumn Int

derive newtype instance Eq ViewColumn
derive newtype instance Ord ViewColumn
derive newtype instance Semiring ViewColumn
derive newtype instance Ring ViewColumn
derive newtype instance Show ViewColumn

-- | Extract the numeric `vscode.ViewColumn` value.
unViewColumn :: ViewColumn -> Int
unViewColumn (ViewColumn n) = n

-- | `vscode.ViewColumn.Beside` (-2): place the editor beside the active one.
beside :: ViewColumn
beside = ViewColumn (-2)

-- | `vscode.ViewColumn.One`.
viewColumnOne :: ViewColumn
viewColumnOne = ViewColumn 1

-- | `vscode.ViewColumn.Two`.
viewColumnTwo :: ViewColumn
viewColumnTwo = ViewColumn 2

-- | `vscode.ViewColumn.Three`.
viewColumnThree :: ViewColumn
viewColumnThree = ViewColumn 3

-- | Register a disposable for cleanup when the extension deactivates
-- | (`context.subscriptions.push(disposable)`).
foreign import pushSubscription :: ExtensionContext -> Disposable -> Effect Unit

-- | Release the resource or registration the disposable owns
-- | (`disposable.dispose()`); idempotent on the stub's disposables.
foreign import dispose :: Disposable -> Effect Unit

-- | The directory the extension is installed in (`context.extensionUri`).
foreign import extensionUri :: ExtensionContext -> Effect Uri

-- | Resolve a path below the given Uri (`vscode.Uri.joinPath(base, …segments)`).
foreign import joinPath :: Uri -> Array String -> Effect Uri

-- | The fully-encoded string form of the Uri (`uri.toString()`).
foreign import uriToString :: Uri -> Effect String
