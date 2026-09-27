-- | Test suite for the shared host↔webview message protocol.
-- |
-- | The wire format is FROZEN: `src/extension.ts` (host) and
-- | `webview-src/src/Webview/Main.purs` (webview) build these payloads today,
-- | and `scripts/smoke.cjs` hard-codes them as the oracle. The stringified
-- | comparisons below pin exact key order, not just deep structure.
module Test.ProtocolMain where

import Prelude

import Data.Argonaut.Core (stringify)
import Data.Argonaut.Parser (jsonParser)
import Data.Array (range)
import Data.Array.NonEmpty (cons')
import Data.Foldable (fold)
import Data.Either (hush)
import Data.Maybe (Maybe(..))
import Data.Traversable (traverse)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Test.QuickCheck (Result(..), (===))
import Test.QuickCheck.Arbitrary (class Arbitrary, arbitrary)
import Test.QuickCheck.Gen (Gen, choose, chooseInt, elements)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.QuickCheck (quickCheck')
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (run)

import GraphProtocol
  ( GraphKind(..)
  , HostUpdate
  , ShowcasePayload
  , ShowcaseSample
  , WebviewToHost(..)
  , decodeHostUpdate
  , decodeShowcase
  , decodeWebviewToHost
  , encodeHostUpdate
  , encodeShowcase
  , encodeWebviewToHost
  , kindFromString
  , kindToString
  , parseJsonToWebviewToHost
  )

-- | Decode a JSON string at the `WebviewToHost` level (mirrors what the host
-- | receives through `onDidReceiveMessage` after FFI wrap).
decodeJsonOf :: String -> Maybe WebviewToHost
decodeJsonOf s = hush (jsonParser s) >>= decodeWebviewToHost

-- | Decode a JSON string at the `HostUpdate` level (mirrors what the webview
-- | receives through `onMessage`).
decodeHostJsonOf :: String -> Maybe HostUpdate
decodeHostJsonOf s = hush (jsonParser s) >>= decodeHostUpdate

-- | Decode a JSON string at the `ShowcasePayload` level (the gallery
-- | direction of `onMessage`).
decodeShowcaseJsonOf :: String -> Maybe ShowcasePayload
decodeShowcaseJsonOf s = hush (jsonParser s) >>= decodeShowcase

-- | Pick one of several string fragments, including JSON-awkward ones
-- | (quotes, backslashes, newlines, non-ASCII) to exercise codec escaping.
genWireString :: Gen String
genWireString = do
  len <- chooseInt 0 10
  fragments <- traverse (const pick) (range 1 len)
  pure (fold fragments)
  where
  pick = elements (cons' "a" [ "b", "dot", "\"", "\\", "\n", "é", "}" ])

newtype ArbKind = ArbKind GraphKind

instance Arbitrary ArbKind where
  arbitrary = map ArbKind $ elements (cons' Dot [ Graph ])

newtype ArbHostUpdate = ArbHostUpdate HostUpdate

instance Arbitrary ArbHostUpdate where
  arbitrary = do
    ArbKind kind <- arbitrary
    source <- genWireString
    fileName <- genWireString
    engine <- genWireString
    pure (ArbHostUpdate { kind, source, fileName, engine })

newtype ArbWebviewToHost = ArbWebviewToHost WebviewToHost

instance Arbitrary ArbWebviewToHost where
  arbitrary = do
    ArbKind kind <- arbitrary
    variant <- chooseInt 0 3
    case variant of
      0 -> pure (ArbWebviewToHost Ready)
      1 -> do
        ms <- choose (-1000000.0) 1000000.0
        pure (ArbWebviewToHost (Rendered kind ms))
      2 -> do
        message <- genWireString
        pure (ArbWebviewToHost (WError kind message))
      _ -> do
        sampleId <- genWireString
        pure (ArbWebviewToHost (OpenSample sampleId))

-- | `HostUpdate` is a type synonym (records get structural `Eq` but no `Show`
-- | instance), so the round-trip property asserts via `Result` directly.
propHostUpdateRoundTrip :: ArbHostUpdate -> Result
propHostUpdateRoundTrip (ArbHostUpdate u) =
  case decodeHostUpdate (encodeHostUpdate u) of
    Just u' | u' == u -> Success
    _ -> Failed "decodeHostUpdate (encodeHostUpdate u) /= Just u"

propWebviewToHostRoundTrip :: ArbWebviewToHost -> Result
propWebviewToHostRoundTrip (ArbWebviewToHost m) =
  decodeWebviewToHost (encodeWebviewToHost m) === Just m

-- | ShowcaseSample is a type synonym (records get structural Eq but no
-- | Show), so the generator builds records of that exact shape.
genShowcaseSample :: Gen ShowcaseSample
genShowcaseSample = do
  ArbKind kind <- arbitrary
  sid <- genWireString
  title <- genWireString
  description <- genWireString
  source <- genWireString
  fileName <- genWireString
  engine <- genWireString
  pure { id: sid, title, description, kind, source, fileName, engine }

newtype ArbShowcasePayload = ArbShowcasePayload ShowcasePayload

instance Arbitrary ArbShowcasePayload where
  arbitrary = do
    n <- chooseInt 0 4
    samples <- traverse (const genShowcaseSample) (range 1 n)
    pure (ArbShowcasePayload { samples })

propShowcaseRoundTrip :: ArbShowcasePayload -> Result
propShowcaseRoundTrip (ArbShowcasePayload p) =
  case decodeShowcase (encodeShowcase p) of
    Just p' | p' == p -> Success
    _ -> Failed "decodeShowcase (encodeShowcase p) /= Just p"

main :: Effect Unit
main = launchAff_ $ run [ consoleReporter ] do
  describe "GraphProtocol" do

    describe "GraphKind" do
      it "maps kinds to their wire labels" do
        kindToString Dot `shouldEqual` "dot"
        kindToString Graph `shouldEqual` "graph"

      it "parses wire labels and rejects everything else" do
        kindFromString "dot" `shouldEqual` Just Dot
        kindFromString "graph" `shouldEqual` Just Graph
        kindFromString "DOT" `shouldEqual` Nothing
        kindFromString "bogus" `shouldEqual` Nothing

    describe "decodeWebviewToHost" do
      it "decodes ready" do
        decodeJsonOf "{\"type\":\"ready\"}" `shouldEqual` Just Ready

      it "decodes rendered with a numeric ms" do
        decodeJsonOf "{\"type\":\"rendered\",\"kind\":\"dot\",\"ms\":12}"
          `shouldEqual` Just (Rendered Dot 12.0)

      it "decodes error with kind and message" do
        decodeJsonOf "{\"type\":\"error\",\"kind\":\"graph\",\"message\":\"boom\"}"
          `shouldEqual` Just (WError Graph "boom")

      it "rejects an unknown kind (silent drop parity)" do
        decodeJsonOf "{\"type\":\"rendered\",\"kind\":\"bogus\",\"ms\":1}" `shouldEqual` Nothing

      it "rejects error without a message field (silent drop parity)" do
        decodeJsonOf "{\"type\":\"error\",\"kind\":\"dot\"}" `shouldEqual` Nothing

      it "rejects an unknown type tag (silent drop parity)" do
        decodeJsonOf "{\"type\":\"nope\"}" `shouldEqual` Nothing

      it "decodes openSample with a string id (showcase)" do
        decodeJsonOf "{\"type\":\"openSample\",\"id\":\"oauth-flow\"}"
          `shouldEqual` Just (OpenSample "oauth-flow")

      it "rejects openSample without a string id (silent drop parity)" do
        decodeJsonOf "{\"type\":\"openSample\"}" `shouldEqual` Nothing
        decodeJsonOf "{\"type\":\"openSample\",\"id\":7}" `shouldEqual` Nothing

      it "rejects non-object payloads (string, number, null, array)" do
        decodeJsonOf "\"hello\"" `shouldEqual` Nothing
        decodeJsonOf "42" `shouldEqual` Nothing
        decodeJsonOf "null" `shouldEqual` Nothing
        decodeJsonOf "[]" `shouldEqual` Nothing

      it "rejects host-direction updates at the webview-to-host gate" do
        decodeJsonOf
          "{\"type\":\"update\",\"kind\":\"dot\",\"source\":\"a\",\"fileName\":\"f\",\"engine\":\"dot\"}"
          `shouldEqual` Nothing

      it "rejects rendered whose ms is not a number (documented strictness)" do
        decodeJsonOf "{\"type\":\"rendered\",\"kind\":\"dot\",\"ms\":\"12\"}" `shouldEqual` Nothing

    describe "decodeHostUpdate" do
      it "rejects a host update missing a required field" do
        decodeHostJsonOf "{\"type\":\"update\",\"kind\":\"dot\",\"source\":\"a\",\"fileName\":\"f\"}"
          `shouldEqual` Nothing

    describe "encodeWebviewToHost" do
      it "encodes ready to the exact wire shape" do
        stringify (encodeWebviewToHost Ready) `shouldEqual` "{\"type\":\"ready\"}"

      it "encodes openSample to the exact wire shape (key-for-key)" do
        stringify (encodeWebviewToHost (OpenSample "ci-pipeline"))
          `shouldEqual` "{\"type\":\"openSample\",\"id\":\"ci-pipeline\"}"

    describe "encodeHostUpdate" do
      it "encodes a host update to the exact wire shape (key-for-key)" do
        let
          u = { kind: Dot, source: "digraph{a}", fileName: "x.dot", engine: "neato" }
        stringify (encodeHostUpdate u)
          `shouldEqual`
            "{\"type\":\"update\",\"kind\":\"dot\",\"source\":\"digraph{a}\",\"fileName\":\"x.dot\",\"engine\":\"neato\"}"

    describe "encodeShowcase" do
      it "encodes a showcase payload to the exact wire shape (key-for-key)" do
        let
          s =
            { id: "s1"
            , title: "T"
            , description: "D"
            , kind: Dot
            , source: "digraph{a}"
            , fileName: "x.dot"
            , engine: "neato"
            }
        stringify (encodeShowcase { samples: [ s ] })
          `shouldEqual`
            "{\"type\":\"showcase\",\"samples\":[{\"id\":\"s1\",\"title\":\"T\",\"description\":\"D\",\"kind\":\"dot\",\"source\":\"digraph{a}\",\"fileName\":\"x.dot\",\"engine\":\"neato\"}]}"

    describe "decodeShowcase" do
      it "decodes a full payload with mixed kinds" do
        decodeShowcaseJsonOf
          "{\"type\":\"showcase\",\"samples\":[{\"id\":\"a\",\"title\":\"A\",\"description\":\"d\",\"kind\":\"dot\",\"source\":\"s\",\"fileName\":\"a.dot\",\"engine\":\"circo\"},{\"id\":\"b\",\"title\":\"B\",\"description\":\"d\",\"kind\":\"graph\",\"source\":\"{}\",\"fileName\":\"b.graph.json\",\"engine\":\"dot\"}]}"
          `shouldEqual` Just
            { samples:
                [ { id: "a", title: "A", description: "d", kind: Dot, source: "s", fileName: "a.dot", engine: "circo" }
                , { id: "b", title: "B", description: "d", kind: Graph, source: "{}", fileName: "b.graph.json", engine: "dot" }
                ]
            }

      it "decodes an empty sample list" do
        decodeShowcaseJsonOf "{\"type\":\"showcase\",\"samples\":[]}" `shouldEqual` Just { samples: [] }

      it "rejects non-showcase type tags (direction separation)" do
        decodeShowcaseJsonOf "{\"type\":\"update\",\"samples\":[]}" `shouldEqual` Nothing
        decodeShowcaseJsonOf "{\"type\":\"ready\"}" `shouldEqual` Nothing

      it "rejects a sample with a missing field" do
        decodeShowcaseJsonOf "{\"type\":\"showcase\",\"samples\":[{\"id\":\"a\"}]}" `shouldEqual` Nothing

      it "rejects a sample with a mistyped field" do
        decodeShowcaseJsonOf
          "{\"type\":\"showcase\",\"samples\":[{\"id\":1,\"title\":\"t\",\"description\":\"d\",\"kind\":\"dot\",\"source\":\"s\",\"fileName\":\"f\",\"engine\":\"e\"}]}"
          `shouldEqual` Nothing

      it "rejects an unknown sample kind" do
        decodeShowcaseJsonOf
          "{\"type\":\"showcase\",\"samples\":[{\"id\":\"a\",\"title\":\"t\",\"description\":\"d\",\"kind\":\"bogus\",\"source\":\"s\",\"fileName\":\"f\",\"engine\":\"e\"}]}"
          `shouldEqual` Nothing

      it "rejects a samples field that is not an array" do
        decodeShowcaseJsonOf "{\"type\":\"showcase\",\"samples\":\"x\"}" `shouldEqual` Nothing

    describe "parseJsonToWebviewToHost" do
      it "parses and decodes a valid message from raw text" do
        parseJsonToWebviewToHost "{\"type\":\"ready\"}" `shouldEqual` Just Ready

      it "yields Nothing on malformed JSON (never throws)" do
        parseJsonToWebviewToHost "not json" `shouldEqual` Nothing
        parseJsonToWebviewToHost "" `shouldEqual` Nothing

    describe "round-trip properties" do
      it "host updates survive encode/decode for 100 samples" do
        quickCheck' 100 propHostUpdateRoundTrip

      it "webview-to-host messages survive encode/decode for 100 samples" do
        quickCheck' 100 propWebviewToHostRoundTrip

      it "showcase payloads survive encode/decode for 100 samples" do
        quickCheck' 100 propShowcaseRoundTrip
