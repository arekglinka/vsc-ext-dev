-- | The shared host↔webview message protocol for Purs Graphs previews.
-- |
-- | This module is the single source of truth for the wire format. It ports
-- | the contract from `src/extension.ts` (the `HostToWebview` interface and
-- | the `WebviewToHost` union with its `toWebviewToHost` validator) and must
-- | remain byte-compatible with the frozen webview smoke oracle in
-- | `scripts/smoke.cjs` and the webview-side construction in
-- | `webview-src/src/Webview/Main.purs`.
-- |
-- | Decoding is strict and total: any malformed payload yields `Nothing`
-- | (never an exception), preserving the host's silent-drop behavior for
-- | messages it cannot understand. Documented deviation from the old
-- | validator: codecs validate every field's type (e.g. `rendered.ms` must be
-- | a JSON number, which the old validator skipped). The deviation is
-- | unobservable in behavior — the host acts only on the `error` case, and
-- | malformed input is dropped either way.
-- |
-- | Encoders build objects field-by-field in wire order, so `stringify`
-- | produces exactly the byte shapes the TS host and PS webview emit today:
-- |
-- |   - host → webview: `{"type":"update","kind":"dot","source":…,"fileName":…,"engine":…}`
-- |   - webview → host: `{"type":"ready"}` / `{"type":"rendered","kind":…,"ms":…}` / `{"type":"error","kind":…,"message":…}`
module GraphProtocol
  ( GraphKind(..)
  , kindToString
  , kindFromString
  , HostUpdate
  , WebviewToHost(..)
  , encodeHostUpdate
  , decodeHostUpdate
  , encodeWebviewToHost
  , decodeWebviewToHost
  , parseJsonToWebviewToHost
  ) where

import Prelude

import Data.Argonaut.Core (Json, fromNumber, fromObject, fromString)
import Data.Argonaut.Decode.Class (decodeJson)
import Data.Argonaut.Decode.Combinators ((.:))
import Data.Argonaut.Decode.Error (JsonDecodeError(..))
import Data.Argonaut.Parser (jsonParser)
import Data.Either (Either(..), hush, note)
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Foreign.Object (Object)
import Foreign.Object as Object

-- | Which of the two graph preview formats a message refers to.
data GraphKind = Dot | Graph

derive instance eqGraphKind :: Eq GraphKind

derive instance ordGraphKind :: Ord GraphKind

instance showGraphKind :: Show GraphKind where
  show = case _ of
    Dot -> "Dot"
    Graph -> "Graph"

-- | Map a `GraphKind` to its wire label (`"dot"` or `"graph"`), matching the
-- | `kind` values the TS host and the webview exchange today.
kindToString :: GraphKind -> String
kindToString = case _ of
  Dot -> "dot"
  Graph -> "graph"

-- | Parse a wire label back into a `GraphKind`. Case-sensitive, like the
-- | `kind === "dot" || kind === "graph"` checks in the TS validator;
-- | anything else yields `Nothing`.
kindFromString :: String -> Maybe GraphKind
kindFromString = case _ of
  "dot" -> Just Dot
  "graph" -> Just Graph
  _ -> Nothing

-- | The host → webview update message body. The `"type": "update"` tag is
-- | added by `encodeHostUpdate` and verified by `decodeHostUpdate`, so
-- | consumers work with the payload fields alone.
type HostUpdate =
  { kind :: GraphKind
  , source :: String
  , fileName :: String
  , engine :: String
  }

-- | Messages sent from the webview back to the extension host, mirroring the
-- | `WebviewToHost` union in `src/extension.ts`.
data WebviewToHost
  = Ready
  | Rendered GraphKind Number
  | WError GraphKind String

derive instance eqWebviewToHost :: Eq WebviewToHost

derive instance ordWebviewToHost :: Ord WebviewToHost

instance showWebviewToHost :: Show WebviewToHost where
  show = case _ of
    Ready -> "Ready"
    Rendered kind ms -> "(Rendered " <> show kind <> " " <> show ms <> ")"
    WError kind message -> "(WError " <> show kind <> " " <> show message <> ")"

-- | Encode a host update into its exact wire shape, key order included:
-- | `{"type":"update","kind":…,"source":…,"fileName":…,"engine":…}`.
encodeHostUpdate :: HostUpdate -> Json
encodeHostUpdate u = fromObject $ Object.fromFoldable
  [ Tuple "type" (fromString "update")
  , Tuple "kind" (fromString (kindToString u.kind))
  , Tuple "source" (fromString u.source)
  , Tuple "fileName" (fromString u.fileName)
  , Tuple "engine" (fromString u.engine)
  ]

-- | Decode a host update. Strict: the payload must be a JSON object with
-- | `type` equal to `"update"`, a valid `kind` label, and `String` values for
-- | `source`, `fileName` and `engine`; anything else yields `Nothing`.
decodeHostUpdate :: Json -> Maybe HostUpdate
decodeHostUpdate json = hush do
  obj <- decodeJson json :: _ (Object Json)
  typ <- obj .: "type"
  case typ of
    "update" -> do
      kind <- kindField obj "kind"
      source <- obj .: "source"
      fileName <- obj .: "fileName"
      engine <- obj .: "engine"
      pure { kind, source, fileName, engine }
    _ -> Left (TypeMismatch "HostUpdate")

-- | Encode a webview-to-host message into its wire shape, key order
-- | included, matching what `Webview/Main.purs` constructs today.
encodeWebviewToHost :: WebviewToHost -> Json
encodeWebviewToHost = case _ of
  Ready -> fromObject $ Object.fromFoldable
    [ Tuple "type" (fromString "ready") ]
  Rendered kind ms -> fromObject $ Object.fromFoldable
    [ Tuple "type" (fromString "rendered")
    , Tuple "kind" (fromString (kindToString kind))
    , Tuple "ms" (fromNumber ms)
    ]
  WError kind message -> fromObject $ Object.fromFoldable
    [ Tuple "type" (fromString "error")
    , Tuple "kind" (fromString (kindToString kind))
    , Tuple "message" (fromString message)
    ]

-- | Decode a webview-to-host message with the same silent-drop semantics as
-- | the TS `toWebviewToHost` validator, but strictly type-checked: `kind`
-- | must be a valid label, `ms` must be a JSON number and `message` must be a
-- | string (see the module header for the documented deviation).
decodeWebviewToHost :: Json -> Maybe WebviewToHost
decodeWebviewToHost json = hush do
  obj <- decodeJson json :: _ (Object Json)
  typ <- obj .: "type"
  case typ of
    "ready" -> pure Ready
    "rendered" -> do
      kind <- kindField obj "kind"
      ms <- obj .: "ms"
      pure (Rendered kind ms)
    "error" -> do
      kind <- kindField obj "kind"
      message <- obj .: "message"
      pure (WError kind message)
    _ -> Left (TypeMismatch "WebviewToHost")

-- | Convenience for host-side message handling: parse a raw JSON text
-- | (as delivered by the webview message channel) into a `WebviewToHost`.
-- | Malformed JSON yields `Nothing` — never throws.
parseJsonToWebviewToHost :: String -> Maybe WebviewToHost
parseJsonToWebviewToHost s = hush (jsonParser s) >>= decodeWebviewToHost

-- | Read and validate the `kind` field of an object payload.
kindField :: Object Json -> String -> Either JsonDecodeError GraphKind
kindField obj key = do
  label <- obj .: key
  note (TypeMismatch ("GraphKind label: " <> label)) (kindFromString label)
