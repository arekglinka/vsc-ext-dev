export const acquireApi = () => acquireVsCodeApi();

export const postMessage = (api) => (msg) => () => api.postMessage(msg);

export const onMessage = (api) => (callback) => () =>
  window.addEventListener("message", (event) => callback(event.data)());

export const nowMs = () => Date.now();

export const setHtmlById = (id) => (html) => () => {
  const el = document.getElementById(id);
  if (el) {
    el.innerHTML = html;
  }
};

export const setTextById = (id) => (text) => () => {
  const el = document.getElementById(id);
  if (el) {
    el.textContent = text;
  }
};

export const addClassById = (id) => (cls) => () => {
  const el = document.getElementById(id);
  if (el) {
    el.classList.add(cls);
  }
};

export const removeClassById = (id) => (cls) => () => {
  const el = document.getElementById(id);
  if (el) {
    el.classList.remove(cls);
  }
};

export const onClickById = (id) => (handler) => () => {
  const el = document.getElementById(id);
  if (el) {
    el.addEventListener("click", handler);
  }
};

export const onFrame = (cb) => () => {
  if (typeof requestAnimationFrame === "function") {
    requestAnimationFrame(() => cb());
  } else {
    setTimeout(() => cb(), 16);
  }
};

export const onMouseMoveById = (id) => (cb) => () => {
  const el = document.getElementById(id);
  if (el) {
    // clientX/Y minus the element's rect — NOT offsetX/Y, which are
    // relative to whichever CHILD is under the pointer (circles, lines)
    // and would feed the engine garbage coordinates over nodes.
    el.addEventListener("mousemove", (event) => {
      const rect = el.getBoundingClientRect();
      cb(event.clientX - rect.left)(event.clientY - rect.top)(rect.width)();
    });
  }
};

export const onMouseLeaveById = (id) => (cb) => () => {
  const el = document.getElementById(id);
  if (el) {
    el.addEventListener("mouseleave", () => cb());
  }
};

// Drag interaction: mousedown reports stage-local coordinates (same
// clientX-rect math as mousemove); mouseup is window-level so a drag that
// ends outside the stage still releases the grabbed node.
export const onDragStartById = (id) => (cb) => () => {
  const el = document.getElementById(id);
  if (el) {
    el.addEventListener("mousedown", (event) => {
      const rect = el.getBoundingClientRect();
      cb(event.clientX - rect.left)(event.clientY - rect.top)(rect.width)();
    });
  }
};

export const onDragEnd = (cb) => () => {
  window.addEventListener("mouseup", () => cb());
};

export const moveNodeById = (id) => (x) => (y) => () => {
  const el = document.getElementById(id);
  if (el) {
    el.setAttribute("transform", `translate(${x} ${y})`);
  }
};

export const setLineById = (id) => (x1) => (y1) => (x2) => (y2) => () => {
  const el = document.getElementById(id);
  if (el) {
    el.setAttribute("x1", String(x1));
    el.setAttribute("y1", String(y1));
    el.setAttribute("x2", String(x2));
    el.setAttribute("y2", String(y2));
  }
};
