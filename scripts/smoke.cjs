// Headless smoke test for the webview bundle: loads media/webview.js in Node
// with stubbed VSCode API + DOM, then drives a DOT render and a graph render
// through the real message protocol. Exit 0 = both render to SVG.
"use strict";
const fs = require("fs");

const code = fs.readFileSync("media/webview.js", "utf8");

const mkEl = () => ({
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
});
const elements = { status: mkEl(), canvas: mkEl() };
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
  listeners["message"]({ data: c.update });
  setTimeout(() => {
    const pass = c.check();
    console.log(`${pass ? "OK  " : "FAIL"}  ${c.name}  (${elements.status.textContent})`);
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
