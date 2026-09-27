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
-- |   - host → webview (showcase): `{"type":"showcase","samples":[{…}]}` (gallery)
-- |   - webview → host (showcase): `{"type":"openSample","id":…}` (Open in editor)
-- |   - host → webview (fluent): `{"type":"fluentPanel","nodes":[…],"edges":[…]}`
module GraphProtocol
  ( GraphKind(..)
  , kindToString
  , kindFromString
  , HostUpdate
  , ShowcaseSample
  , ShowcasePayload
  , FluentNode
  , FluentEdge
  , FluentPayload
  , WebviewToHost(..)
  , encodeHostUpdate
  , decodeHostUpdate
  , encodeShowcase
  , decodeShowcase
  , encodeFluentPanel
  , decodeFluentPanel
  , encodeWebviewToHost
  , decodeWebviewToHost
  , parseJsonToWebviewToHost
  ) where

import Prelude

import Data.Argonaut.Core (Json, fromArray, fromNumber, fromObject, fromString)
import Data.Argonaut.Decode.Class (decodeJson)
import Data.Argonaut.Decode.Combinators ((.:))
import Data.Argonaut.Decode.Error (JsonDecodeError(..))
import Data.Argonaut.Parser (jsonParser)
import Data.Either (Either(..), hush, note)
import Data.Maybe (Maybe(..))
import Data.Traversable (traverse)
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

-- | One demo entry in the showcase gallery. `kind` picks the renderer
-- | (DOT via viz.js, JSON spec via dagre); `engine` is the Graphviz engine
-- | used for DOT samples (ignored for `Graph`).
type ShowcaseSample =
  { id :: String
  , title :: String
  , description :: String
  , kind :: GraphKind
  , source :: String
  , fileName :: String
  , engine :: String
  }

-- | The host → webview showcase payload: the full sample list, sent whenever
-- | the showcase panel is created or re-revealed. The `"type": "showcase"`
-- | tag is added by `encodeShowcase` and verified by `decodeShowcase`.
type ShowcasePayload =
  { samples :: Array ShowcaseSample
  }

-- | Messages sent from the webview back to the extension host, mirroring the
-- | `WebviewToHost` union in `src/extension.ts` (plus the showcase-only
-- | `OpenSample` addition).
data WebviewToHost
  = Ready
  | Rendered GraphKind Number
  | WError GraphKind String
  | OpenSample String

derive instance eqWebviewToHost :: Eq WebviewToHost

derive instance ordWebviewToHost :: Ord WebviewToHost

instance showWebviewToHost :: Show WebviewToHost where
  show = case _ of
    Ready -> "Ready"
    Rendered kind ms -> "(Rendered " <> show kind <> " " <> show ms <> ")"
    WError kind message -> "(WError " <> show kind <> " " <> show message <> ")"
    OpenSample sampleId -> "(OpenSample " <> show sampleId <> ")"

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

-- | Encode a showcase payload into its exact wire shape, key order included:
-- | `{"type":"showcase","samples":[{"id":…,"title":…,"description":…,
-- | "kind":…,"source":…,"fileName":…,"engine":…},…]}`.
encodeShowcase :: ShowcasePayload -> Json
encodeShowcase p = fromObject $ Object.fromFoldable
  [ Tuple "type" (fromString "showcase")
  , Tuple "samples" (fromArray (map encodeSample p.samples))
  ]

encodeSample :: ShowcaseSample -> Json
encodeSample s = fromObject $ Object.fromFoldable
  [ Tuple "id" (fromString s.id)
  , Tuple "title" (fromString s.title)
  , Tuple "description" (fromString s.description)
  , Tuple "kind" (fromString (kindToString s.kind))
  , Tuple "source" (fromString s.source)
  , Tuple "fileName" (fromString s.fileName)
  , Tuple "engine" (fromString s.engine)
  ]

-- | Decode a showcase payload. Strict: the payload must be a JSON object with
-- | `type` equal to `"showcase"` and a `samples` array whose entries each
-- | carry the seven showcase fields with valid types; anything else yields
-- | `Nothing` (silent drop, like every other decoder here).
decodeShowcase :: Json -> Maybe ShowcasePayload
decodeShowcase json = hush do
  obj <- decodeJson json :: _ (Object Json)
  typ <- obj .: "type"
  case typ of
    "showcase" -> do
      rawSamples <- obj .: "samples"
      samples <- traverse decodeSampleField rawSamples
      pure { samples }
    _ -> Left (TypeMismatch "ShowcasePayload")

decodeSampleField :: Json -> Either JsonDecodeError ShowcaseSample
decodeSampleField json = do
  obj <- decodeJson json :: _ (Object Json)
  sampleId <- obj .: "id"
  title <- obj .: "title"
  description <- obj .: "description"
  kind <- kindField obj "kind"
  source <- obj .: "source"
  fileName <- obj .: "fileName"
  engine <- obj .: "engine"
  pure { id: sampleId, title, description, kind, source, fileName, engine }

-- | The host → webview fluent-panel payload: the graph the Rust/WASM force
-- | simulation animates. Node identity is the id string; the webview maps
-- | ids to wasm array indices.
type FluentNode =
  { id :: String
  , label :: String
  }

type FluentEdge =
  { from :: String
  , to :: String
  }

type FluentPayload =
  { nodes :: Array FluentNode
  , edges :: Array FluentEdge
  }

-- | Encode a fluent-panel payload into its exact wire shape, key order
-- | included:
-- | `{"type":"fluentPanel","nodes":[{"id":…,"label":…}],"edges":[{"from":…,"to":…}]}`.
encodeFluentPanel :: FluentPayload -> Json
encodeFluentPanel p = fromObject $ Object.fromFoldable
  [ Tuple "type" (fromString "fluentPanel")
  , Tuple "nodes" (fromArray (map encodeFluentNode p.nodes))
  , Tuple "edges" (fromArray (map encodeFluentEdge p.edges))
  ]

encodeFluentNode :: FluentNode -> Json
encodeFluentNode nd = fromObject $ Object.fromFoldable
  [ Tuple "id" (fromString nd.id)
  , Tuple "label" (fromString nd.label)
  ]

encodeFluentEdge :: FluentEdge -> Json
encodeFluentEdge e = fromObject $ Object.fromFoldable
  [ Tuple "from" (fromString e.from)
  , Tuple "to" (fromString e.to)
  ]

-- | Decode a fluent-panel payload. Strict: `type` must equal
-- | `"fluentPanel"`, `nodes`/`edges` must be arrays of two-string records;
-- | anything else yields `Nothing` (silent drop, like every decoder here).
decodeFluentPanel :: Json -> Maybe FluentPayload
decodeFluentPanel json = hush do
  obj <- decodeJson json :: _ (Object Json)
  typ <- obj .: "type"
  case typ of
    "fluentPanel" -> do
      nodes <- traverse decodeFluentNodeField =<< obj .: "nodes"
      edges <- traverse decodeFluentEdgeField =<< obj .: "edges"
      pure { nodes, edges }
    _ -> Left (TypeMismatch "FluentPayload")

decodeFluentNodeField :: Json -> Either JsonDecodeError FluentNode
decodeFluentNodeField json = do
  obj <- decodeJson json :: _ (Object Json)
  nid <- obj .: "id"
  label <- obj .: "label"
  pure { id: nid, label }

decodeFluentEdgeField :: Json -> Either JsonDecodeError FluentEdge
decodeFluentEdgeField json = do
  obj <- decodeJson json :: _ (Object Json)
  from <- obj .: "from"
  to <- obj .: "to"
  pure { from, to }

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
  OpenSample sampleId -> fromObject $ Object.fromFoldable
    [ Tuple "type" (fromString "openSample")
    , Tuple "id" (fromString sampleId)
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
    "openSample" -> do
      sampleId <- obj .: "id"
      pure (OpenSample sampleId)
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
