// @viz-js/viz is an npm peer-dependency (@viz-js/viz 3.x). Consumers must
// install it; it is NOT bundled here so the dependency can be deduped.
import { instance as vizInstance } from "@viz-js/viz";

// Start async instance creation. Invokes onSuccess with the Viz instance or
// onFailure with an error message string. Curried to match the PureScript
// foreign import signature (two function args, returning an Effect thunk).
export function _startInstance(onSuccess) {
  return (onFailure) => () => {
    vizInstance().then(
      (viz) => {
        onSuccess(viz)();
      },
      (err) => {
        const msg = err == null ? "viz.js instance creation failed" : err.message || String(err);
        onFailure(msg)();
      }
    );
  };
}

// Synchronous render using viz.render() which returns a result object and
// never throws on DOT errors. The try/catch guards against unexpected runtime
// errors so no exceptions cross the FFI boundary.
export function _render(viz, input, format, engine) {
  try {
    return viz.render(input, { format: format, engine: engine });
  } catch (e) {
    return {
      status: "failure",
      output: null,
      errors: [{ level: "error", message: String(e?.message || e) }],
    };
  }
}
