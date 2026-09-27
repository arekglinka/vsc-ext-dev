// Dev-only stub of the `vscode` module. Implements EXACTLY the API surface used
// by src/extension.ts plus the showcase-gallery surface
// (openTextDocument/showTextDocument) — a test double that records calls and
// resolves promises, never mimicking real VSCode behavior. All recordings are reachable through
// the `__stub` namespace; `__stub.reset()` clears state between tests (state is
// per-process, arrays keep identity across resets).

const state = {
  commands: [],
  panels: [],
  errorMessages: [],
  postMessages: [],
  openedDocuments: [],
  shownDocuments: [],
  docChangeListeners: [],
  disposeListeners: [],
  messageListeners: [],
  config: {},
  activeTextEditor: undefined,
  untitledSeq: 0,
};

function removeFrom(list, entry) {
  const i = list.indexOf(entry);
  if (i >= 0) list.splice(i, 1);
}

function makeDisposable(onDispose) {
  let disposed = false;
  return {
    dispose() {
      if (disposed) return;
      disposed = true;
      onDispose();
    },
  };
}

function subscribe(list, makeEntry, disposables) {
  const entry = makeEntry();
  list.push(entry);
  const disposable = makeDisposable(() => removeFrom(list, entry));
  if (Array.isArray(disposables)) disposables.push(disposable);
  return disposable;
}

const commands = {
  registerCommand(id, handler) {
    const entry = { id, handler };
    state.commands.push(entry);
    return makeDisposable(() => removeFrom(state.commands, entry));
  },
};

function createWebviewPanel(viewType, title, showOptions, options) {
  const panel = {
    viewType,
    title,
    showOptions,
    options,
    visible: true,
    reveals: [],
    reveal(column) {
      panel.reveals.push(column);
    },
    onDidDispose(callback, thisArg, disposables) {
      return subscribe(state.disposeListeners, () => ({ panel, callback, thisArg }), disposables);
    },
  };
  const webview = {};
  let html;
  Object.defineProperty(webview, "html", {
    get() {
      return html;
    },
    set(value) {
      html = value;
    },
  });
  webview.onDidReceiveMessage = (callback, thisArg, disposables) =>
    subscribe(state.messageListeners, () => ({ panel, webview, callback, thisArg }), disposables);
  // MUST always resolve: a rejection would crash Node 22 as an unhandled rejection.
  webview.postMessage = (message) => {
    state.postMessages.push(message);
    return Promise.resolve(true);
  };
  webview.asWebviewUri = (uri) => ({
    toString: () => `vscode-webview-resource://${uri.path ?? uri.toString()}`,
  });
  panel.webview = webview;
  state.panels.push(panel);
  return panel;
}

const window = {
  get activeTextEditor() {
    return state.activeTextEditor;
  },
  set activeTextEditor(editor) {
    state.activeTextEditor = editor;
  },
  showErrorMessage(message) {
    state.errorMessages.push(message);
    return Promise.resolve();
  },
  createWebviewPanel,
  // Records the shown document and activates an editor for it. MUST resolve:
  // a rejection would crash Node 22 as an unhandled rejection.
  showTextDocument(document) {
    state.shownDocuments.push(document);
    const editor = { document, viewColumn: 1 };
    state.activeTextEditor = editor;
    return Promise.resolve(editor);
  },
};

const workspace = {
  onDidChangeTextDocument(callback, thisArg, disposables) {
    return subscribe(state.docChangeListeners, () => ({ callback, thisArg }), disposables);
  },
  // The untitled-document overload ({ language, content }) used by the
  // showcase gallery. Returns synchronously — the PS binding is a plain
  // Effect, matching the stub-sync convention of the other bindings.
  openTextDocument(options) {
    if (options && typeof options === "object" && typeof options.content === "string") {
      state.untitledSeq += 1;
      const name = `Untitled-${state.untitledSeq}`;
      const doc = {
        fileName: name,
        languageId: options.language ?? "plaintext",
        uri: { toString: () => `untitled:${name}` },
        getText: () => options.content,
      };
      state.openedDocuments.push(doc);
      return doc;
    }
    return undefined;
  },
  getConfiguration(section) {
    return {
      get(key, defaultValue) {
        return state.config[section]?.[key] ?? defaultValue;
      },
    };
  },
};

const Uri = {
  joinPath(base, ...segments) {
    return { toString: () => `${base.toString()}/${segments.join("/")}` };
  },
};

const RESETTABLE_LISTS = [
  "commands",
  "panels",
  "errorMessages",
  "postMessages",
  "docChangeListeners",
  "disposeListeners",
  "messageListeners",
  "openedDocuments",
  "shownDocuments",
];

const __stub = {
  commands: state.commands,
  panels: state.panels,
  errorMessages: state.errorMessages,
  postMessages: state.postMessages,
  openedDocuments: state.openedDocuments,
  shownDocuments: state.shownDocuments,
  docChangeListeners: state.docChangeListeners,
  disposeListeners: state.disposeListeners,
  messageListeners: state.messageListeners,
  config: state.config,
  makeContext() {
    return {
      extensionUri: { toString: () => "file:///ext" },
      subscriptions: [],
    };
  },
  textDocument({ fileName, languageId, text }) {
    return {
      fileName,
      languageId,
      uri: { toString: () => `file:///ws/${fileName}` },
      getText: () => text,
    };
  },
  setActiveTextEditor(editor) {
    state.activeTextEditor = editor;
  },
  setConfiguration(section, key, value) {
    state.config[section] = { ...state.config[section], [key]: value };
  },
  emitDocChange(document) {
    const event = { document };
    for (const entry of [...state.docChangeListeners]) {
      entry.callback.call(entry.thisArg, event);
    }
  },
  reset() {
    for (const key of RESETTABLE_LISTS) {
      state[key].length = 0;
    }
    for (const key of Object.keys(state.config)) {
      delete state.config[key];
    }
    state.activeTextEditor = undefined;
    state.untitledSeq = 0;
  },
};

module.exports = {
  commands,
  window,
  workspace,
  Uri,
  ViewColumn: { Beside: -2, One: 1, Two: 2 },
  __stub,
};
