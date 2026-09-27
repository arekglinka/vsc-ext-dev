// Test-only FFI: drives the dev-only vscode stub (node_modules/vscode) directly.
// Kept out of src/ so the library surface ships zero test scaffolding. The
// default import is load-bearing — see src/Vscode/Version.js for why
// `import * as vscode` breaks under Node's native CJS-ESM interop.
import vscode from "vscode";

export const makeContext = () => vscode.__stub.makeContext();

export const subscriptionsLength = (context) => () => context.subscriptions.length;

export const makeFakeDisposable = () =>
  vscode.commands.registerCommand("Test.VscodeMain.fake", () => {});

export const stubCommandsLength = () => vscode.__stub.commands.length;

export const resetStub = () => vscode.__stub.reset();
