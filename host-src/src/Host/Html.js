// FFI for Host.Html — verbatim port of getNonce from src/extension.ts:206-213.
// Deliberately dependency-free (pure JS + Math.random; no crypto upgrade —
// documented parity decision in the migration plan).
export const getNonceImpl = () => {
  let text = "";
  const possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  for (let i = 0; i < 32; i++) {
    text += possible.charAt(Math.floor(Math.random() * possible.length));
  }
  return text;
};
