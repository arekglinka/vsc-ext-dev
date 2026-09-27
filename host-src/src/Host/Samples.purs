-- | The demo gallery shipped with the **Purs Graphs: Showcase Gallery**
-- | command (`pursGraphs.showcase`). Every sample lives right here in
-- | PureScript: the two `.dot` and two `.graph.json` entries mirror the
-- | files in `samples/` verbatim, and the cluster + radial entries are
-- | gallery-exclusive demos of what the two renderers can do.
module Host.Samples
  ( showcaseSamples
  , fluentGraph
  ) where

import GraphProtocol (FluentPayload, GraphKind(..), ShowcaseSample)

ciPipelineSource :: String
ciPipelineSource =
  """
digraph ci_pipeline {
  rankdir=LR;
  node [shape=box, style="rounded,filled", fillcolor="#eef4fb", fontname="sans-serif", fontsize=11];
  edge [fontname="sans-serif", fontsize=9];

  push [label="git push"];
  build [label="Build"];
  unit [label="Unit tests"];
  lint [label="Lint + format"];
  scan [label="Security scan"];
  docker [label="Docker image"];
  stage [label="Deploy staging"];
  e2e [label="E2E tests"];
  approve [label="Manual approval", shape=diamond, fillcolor="#fdf6e3"];
  canary [label="Canary 5%"];
  prod [label="Production 100%", fillcolor="#e8f5e9"];

  push -> build;
  build -> unit;
  build -> lint;
  unit -> scan;
  lint -> scan;
  scan -> docker;
  docker -> stage;
  stage -> e2e;
  e2e -> approve;
  approve -> canary;
  canary -> prod;
}
"""

oauthFlowSource :: String
oauthFlowSource =
  """
digraph oauth2 {
  rankdir=LR;
  node [shape=box, style=rounded, fontname="sans-serif", fontsize=11];
  edge [fontname="sans-serif", fontsize=9];

  user [label="User (resource owner)"];
  app [label="Client app"];
  auth [label="Authorization server"];
  api [label="Resource server / API"];

  user -> app [label="1. click 'Sign in'"];
  app -> auth [label="2. redirect /authorize\n(client_id, scope, PKCE)"];
  auth -> user [label="3. login + consent"];
  user -> auth [label="4. approve"];
  auth -> app [label="5. redirect ?code=..."];
  app -> auth [label="6. POST /token\n(code + PKCE verifier)"];
  auth -> app [label="7. access_token (+ refresh)"];
  app -> api [label="8. Bearer token"];
  api -> app [label="9. 200 OK"];
}
"""

serviceMeshSource :: String
serviceMeshSource =
  """
digraph service_mesh {
  rankdir=LR;
  node [shape=box, style="rounded,filled", fillcolor="#eef4fb", fontname="sans-serif", fontsize=11];
  edge [fontname="sans-serif", fontsize=9];

  subgraph cluster_edge {
    label="Edge"; style="rounded,dashed"; color="#9aa4b2";
    cdn [label="CDN"];
    waf [label="WAF", fillcolor="#fdf6e3"];
  }

  subgraph cluster_api {
    label="API tier"; style="rounded"; color="#5b8def";
    gw [label="API gateway", fillcolor="#e8f0fe"];
    orders [label="Orders svc"];
    carts [label="Carts svc"];
  }

  subgraph cluster_data {
    label="Data tier"; style="rounded"; color="#3aa675";
    pg [label="Postgres", shape=cylinder, fillcolor="#e8f5e9"];
    redis [label="Redis", shape=cylinder, fillcolor="#e8f5e9"];
  }

  cdn -> waf [label="HTTPS"];
  waf -> gw;
  gw -> orders [label="REST"];
  gw -> carts [label="REST"];
  orders -> pg [label="SQL"];
  orders -> redis [label="cache"];
  carts -> pg [label="SQL"];
}
"""

dependencyRadarSource :: String
dependencyRadarSource =
  """
digraph dependency_radar {
  node [shape=ellipse, style=filled, fillcolor="#eef4fb", fontname="sans-serif", fontsize=10];
  edge [color="#7a8aa0", fontname="sans-serif", fontsize=8];

  core [label="purs core", fillcolor="#fdf6e3"];
  argonaut [label="argonaut"];
  dagre [label="dagre"];
  viz [label="viz.js"];
  vscodeapi [label="vscode API"];
  esbuild [label="esbuild"];
  protocol [label="protocol", fillcolor="#e8f0fe"];
  host [label="host", fillcolor="#e8f0fe"];
  webview [label="webview", fillcolor="#e8f5e9"];

  core -> argonaut;
  core -> dagre;
  core -> viz;
  core -> vscodeapi;
  protocol -> argonaut;
  host -> protocol;
  host -> vscodeapi;
  webview -> protocol;
  webview -> viz;
  webview -> dagre;
  esbuild -> host [style=dashed, label="bundle"];
  esbuild -> webview [style=dashed, label="bundle"];
}
"""

systemDesignSource :: String
systemDesignSource =
  """
{
  "rankDir": "LR",
  "nodes": [
    { "id": "client", "label": "Browser", "width": 110, "height": 50 },
    { "id": "cdn", "label": "CDN", "width": 90, "height": 50 },
    { "id": "lb", "label": "Load Balancer", "width": 140, "height": 50 },
    { "id": "api1", "label": "API Server 1", "width": 130, "height": 50 },
    { "id": "api2", "label": "API Server 2", "width": 130, "height": 50 },
    { "id": "cache", "label": "Redis Cache", "width": 130, "height": 50 },
    { "id": "db", "label": "Postgres", "width": 110, "height": 50 },
    { "id": "replica", "label": "Read Replica", "width": 130, "height": 50 },
    { "id": "queue", "label": "Kafka", "width": 100, "height": 50 },
    { "id": "worker", "label": "Workers", "width": 110, "height": 50 }
  ],
  "edges": [
    { "from": "client", "to": "cdn", "label": "HTTPS" },
    { "from": "client", "to": "lb", "label": "API calls" },
    { "from": "lb", "to": "api1" },
    { "from": "lb", "to": "api2" },
    { "from": "api1", "to": "cache", "label": "get/set" },
    { "from": "api2", "to": "cache", "label": "get/set" },
    { "from": "api1", "to": "db", "label": "writes" },
    { "from": "api2", "to": "db", "label": "writes" },
    { "from": "api1", "to": "replica", "label": "reads" },
    { "from": "api2", "to": "replica", "label": "reads" },
    { "from": "db", "to": "queue", "label": "CDC" },
    { "from": "queue", "to": "worker", "label": "consume" }
  ]
}
"""

kafkaTopicsSource :: String
kafkaTopicsSource =
  """
{
  "rankDir": "TB",
  "nodes": [
    { "id": "orders", "label": "orders", "width": 110, "height": 45 },
    { "id": "payments", "label": "payments", "width": 110, "height": 45 },
    { "id": "shipments", "label": "shipments", "width": 120, "height": 45 },
    { "id": "analytics", "label": "analytics", "width": 120, "height": 45 },
    { "id": "checkout", "label": "Checkout Service", "width": 160, "height": 50 },
    { "id": "billing", "label": "Billing Service", "width": 150, "height": 50 },
    { "id": "fulfil", "label": "Fulfilment Service", "width": 165, "height": 50 },
    { "id": "dash", "label": "Analytics Dashboard", "width": 175, "height": 50 }
  ],
  "edges": [
    { "from": "checkout", "to": "orders", "label": "OrderCreated" },
    { "from": "checkout", "to": "payments", "label": "PaymentRequested" },
    { "from": "billing", "to": "payments", "label": "PaymentCaptured" },
    { "from": "billing", "to": "shipments", "label": "PaymentConfirmed" },
    { "from": "fulfil", "to": "shipments", "label": "ShipmentBooked" },
    { "from": "orders", "to": "analytics", "label": "repartition" },
    { "from": "payments", "to": "analytics", "label": "repartition" },
    { "from": "shipments", "to": "analytics", "label": "repartition" },
    { "from": "analytics", "to": "dash" }
  ]
}
"""

-- | The graph animated by the fluent panel (`pursGraphs.fluentPanel`):
-- | this extension's own architecture, breathed into motion by the Rust/WASM
-- | force simulation (springs + repulsion, pointer-reactive).
fluentGraph :: FluentPayload
fluentGraph =
  { nodes:
      [ { id: "browser", label: "Browser" }
      , { id: "cdn", label: "CDN" }
      , { id: "lb", label: "Load Balancer" }
      , { id: "api", label: "API Server" }
      , { id: "cache", label: "Redis" }
      , { id: "db", label: "Postgres" }
      , { id: "queue", label: "Kafka" }
      , { id: "worker", label: "Workers" }
      , { id: "host", label: "PS Host" }
      , { id: "webview", label: "PS Webview" }
      , { id: "viz", label: "viz.js" }
      , { id: "dagre", label: "dagre" }
      ]
  , edges:
      [ { from: "browser", to: "cdn" }
      , { from: "browser", to: "lb" }
      , { from: "cdn", to: "lb" }
      , { from: "lb", to: "api" }
      , { from: "api", to: "cache" }
      , { from: "api", to: "db" }
      , { from: "db", to: "queue" }
      , { from: "queue", to: "worker" }
      , { from: "host", to: "webview" }
      , { from: "host", to: "api" }
      , { from: "webview", to: "viz" }
      , { from: "webview", to: "dagre" }
      ]
  }

-- | The ordered gallery: the two repo DOT demos, the two gallery-exclusive
-- | DOT feature demos, then the two JSON-spec (dagre) demos.
showcaseSamples :: Array ShowcaseSample
showcaseSamples =
  [ { id: "ci-pipeline"
    , title: "CI Pipeline"
    , description: "A layered CI pipeline — branching, joins, and a manual-approval gate, rendered by the dot engine."
    , kind: Dot
    , source: ciPipelineSource
    , fileName: "ci-pipeline.dot"
    , engine: "dot"
    }
  , { id: "oauth-flow"
    , title: "OAuth 2.0 Flow"
    , description: "The authorization-code flow with numbered, multi-line edge labels — all plain Graphviz DOT."
    , kind: Dot
    , source: oauthFlowSource
    , fileName: "oauth-flow.dot"
    , engine: "dot"
    }
  , { id: "service-mesh"
    , title: "Clustered Service Mesh"
    , description: "Subgraph clusters, per-node styling, and node shapes (cylinders for stores) from one DOT file."
    , kind: Dot
    , source: serviceMeshSource
    , fileName: "service-mesh.dot"
    , engine: "dot"
    }
  , { id: "dependency-radar"
    , title: "Extension Dependency Radar"
    , description: "How this very extension is built — the same DOT data laid out radially by the circo engine."
    , kind: Dot
    , source: dependencyRadarSource
    , fileName: "dependency-radar.dot"
    , engine: "circo"
    }
  , { id: "system-design"
    , title: "System Design (JSON)"
    , description: "A JSON graph spec laid out left-to-right by dagre — the format previewed from *.graph.json files."
    , kind: Graph
    , source: systemDesignSource
    , fileName: "system-design.graph.json"
    , engine: "dot"
    }
  , { id: "kafka-topics"
    , title: "Kafka Topics (JSON)"
    , description: "Event flow between services and Kafka topics from a JSON spec — dagre top-to-bottom layout."
    , kind: Graph
    , source: kafkaTopicsSource
    , fileName: "kafka-topics.graph.json"
    , engine: "dot"
    }
  ]
