// dagre is an npm peer-dependency (dagre@0.8.5). Consumers must install it;
// it is NOT bundled here so the dependency can be deduped across the tree.
import dagre from "dagre";

export function newGraph() {
  const g = new dagre.graphlib.Graph();
  g.setGraph({});
  g.setDefaultEdgeLabel(() => ({}));
  return g;
}

export function setRankDir(g) {
  return (dir) => () => {
    const label = g.graph();
    if (label) {
      label.rankdir = dir;
    }
  };
}

export function setNodeImpl(g) {
  return (id) => (dims) => (labelText) => () => {
    g.setNode(id, {
      width: dims.width,
      height: dims.height,
      label: labelText,
    });
  };
}

export function setEdgeImpl(g) {
  return (source) => (target) => () => {
    g.setEdge(source, target, {});
  };
}

export function layoutImpl(g) {
  return () => {
    dagre.layout(g);
  };
}

export function nodeX(g) {
  return (id) => () => {
    const node = g.node(id);
    return node ? node.x : null;
  };
}

export function nodeY(g) {
  return (id) => () => {
    const node = g.node(id);
    return node ? node.y : null;
  };
}

export function nodes(g) {
  return () => g.nodes();
}

export function graphWidth(g) {
  return () => {
    const label = g.graph();
    return label ? label.width : null;
  };
}

export function graphHeight(g) {
  return () => {
    const label = g.graph();
    return label ? label.height : null;
  };
}
