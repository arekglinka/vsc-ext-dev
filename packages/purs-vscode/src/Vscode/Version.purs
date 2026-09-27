module Vscode.Version where

import Prelude

import Effect (Effect)

-- | Spike binding: `true` when the FFI `import * as vscode from "vscode"`
-- | resolved to the dev-only stub (`vendor/vscode-stub`) rather than failing.
-- | Proves bare-specifier `vscode` resolution under spago's esbuild test bundler.
foreign import stubActive :: Effect Boolean
