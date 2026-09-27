// Headless smoke test for the webview bundle: loads media/webview.js in Node
// with stubbed VSCode API + DOM, then drives a DOT render, a graph render,
// and the showcase gallery (nav build, sample switch, Open-in-editor click)
// through the real message protocol. Exit 0 = all render to SVG.
"use strict";
const fs = require("node:fs");

const code = fs.readFileSync("media/webview.js", "utf8");

const mkEl = () => {
  const listeners = {};
  return {
    textContent: "",
    innerHTML: "",
    classList: {
      _s: new Set(),
      add(c) {
        this._s.add(c);
      },
      remove(c) {
        this._s.delete(c);
      },
    },
    addEventListener(type, fn) {
      (listeners[type] ??= []).push(fn);
    },
    click() {
      for (const fn of listeners.click ?? []) fn({});
    },
    setAttribute(name, value) {
      this.attrs ??= {};
      this.attrs[name] = value;
    },
  };
};
const elements = {
  status: mkEl(),
  canvas: mkEl(),
  // gallery anchors (showcase mode); nav buttons are pre-registered because
  // innerHTML in this harness does not materialize elements.
  nav: mkEl(),
  desc: mkEl(),
  "open-editor": mkEl(),
  "pg-nav-0": mkEl(),
  "pg-nav-1": mkEl(),
  // fluent-panel anchors: the stage SVG is injected via innerHTML (not
  // materialized in this harness), so the node/edge elements the animation
  // moves every frame are pre-registered with the same ids.
  stage: mkEl(),
  "fluent-n-0": mkEl(),
  "fluent-n-1": mkEl(),
  "fluent-n-2": mkEl(),
  "fluent-e-0": mkEl(),
  "fluent-e-1": mkEl(),
};
global.document = { getElementById: (id) => elements[id] ?? null };
const listeners = {};
global.window = {
  addEventListener: (t, fn) => {
    listeners[t] = fn;
  },
};
const hostMessages = [];
global.acquireVsCodeApi = () => ({
  postMessage: (m) => {
    hostMessages.push(m);
    if (m.type === "ready") hostMessages.ready = true;
  },
});

(0, eval)(code);

const cases = [
  {
    name: "dot",
    update: {
      type: "update",
      kind: "dot",
      source: "digraph{a->b}",
      engine: "dot",
      fileName: "t.dot",
    },
    check: () =>
      elements.canvas.innerHTML.includes("<svg") && !elements.status.classList._s.has("error"),
  },
  {
    name: "graph",
    update: {
      type: "update",
      kind: "graph",
      source: JSON.stringify({
        rankDir: "LR",
        nodes: [
          { id: "a", label: "API" },
          { id: "b", label: "DB" },
        ],
        edges: [{ from: "a", to: "b" }],
      }),
      engine: "dot",
      fileName: "t.graph.json",
    },
    check: () =>
      elements.canvas.innerHTML.includes("<svg") &&
      elements.canvas.innerHTML.includes('class="pg-node"') &&
      !elements.status.classList._s.has("error"),
  },
  {
    name: "showcase",
    update: {
      type: "showcase",
      samples: [
        {
          id: "s-dot",
          title: "Dot Sample",
          description: "a dot demo",
          kind: "dot",
          source: "digraph{a->b}",
          fileName: "s.dot",
          engine: "dot",
        },
        {
          id: "s-graph",
          title: "Graph Sample",
          description: "a graph demo",
          kind: "graph",
          source: JSON.stringify({
            rankDir: "LR",
            nodes: [
              { id: "x", label: "X" },
              { id: "y", label: "Y" },
            ],
            edges: [{ from: "x", to: "y" }],
          }),
          fileName: "s.graph.json",
          engine: "dot",
        },
      ],
    },
    check: () =>
      elements.nav.innerHTML.includes("Dot Sample") &&
      elements.nav.innerHTML.includes("pg-nav-1") &&
      elements.canvas.innerHTML.includes("<svg") &&
      elements.desc.textContent === "a dot demo" &&
      !elements.status.classList._s.has("error"),
    // After the initial render: click nav button 1 (switch to the JSON
    // sample), then the Open-in-editor button (must post openSample with the
    // SELECTED sample id).
    after: () => {
      elements["pg-nav-1"].click();
      const switched =
        elements.desc.textContent === "a graph demo" &&
        elements.canvas.innerHTML.includes('class="pg-node"');
      elements["open-editor"].click();
      const opened = hostMessages.some((m) => m && m.type === "openSample" && m.id === "s-graph");
      return switched && opened;
    },
  },
  {
    name: "fluent",
    update: {
      type: "fluentPanel",
      nodes: [
        { id: "a", label: "Rust" },
        { id: "b", label: "WASM" },
        { id: "c", label: "PureScript" },
      ],
      edges: [
        { from: "a", to: "b" },
        { from: "b", to: "c" },
      ],
    },
    check: () =>
      elements.canvas.innerHTML.includes('class="fluent-node"') &&
      // the Rust engine must have stepped and moved at least one node
      // (transform written through the zero-copy Float32 view).
      Boolean(elements["fluent-n-0"].attrs?.transform) &&
      !elements.status.classList._s.has("error"),
  },
];

let i = 0;
function next() {
  if (!hostMessages.ready) return setTimeout(next, 100);
  if (i >= cases.length) {
    const ok = hostMessages.some((m) => m && m.type === "rendered");
    console.log("SMOKE OK — rendered messages:", JSON.stringify(hostMessages.filter(Boolean)));
    process.exit(ok ? 0 : 1);
  }
  const c = cases[i];
  listeners.message({ data: c.update });
  setTimeout(() => {
    let pass = c.check();
    let label = c.name;
    if (pass && c.after) {
      pass = c.after();
      label = `${c.name} (+interactions)`;
    }
    console.log(`${pass ? "OK  " : "FAIL"}  ${label}  (${elements.status.textContent})`);
    if (!pass) process.exit(1);
    i++;
    next();
  }, 700);
}
setTimeout(next, 200);
setTimeout(() => {
  console.error("SMOKE TIMEOUT — webview never signalled ready");
  process.exit(1);
}, 15000);
