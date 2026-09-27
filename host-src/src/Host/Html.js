// FFI for Host.Html — Math.random only; the nonce construction itself is
// PureScript (same 32-char alphabet and distribution as the original
// src/extension.ts:206-213 port; randomness-source is a documented parity
// decision, deliberately not crypto).
export const mathRandom = () => Math.random();
