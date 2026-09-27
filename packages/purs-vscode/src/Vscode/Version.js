// vscode resolves to the dev-only stub in node_modules. The default import is
// load-bearing: under Node's native CJS-ESM interop, `import * as vscode` does
// not surface `__stub` (or `ViewColumn`) on the namespace — only the default
// export is the full `module.exports`.
import vscode from "vscode";

export const stubActive = () => vscode.__stub !== undefined;
