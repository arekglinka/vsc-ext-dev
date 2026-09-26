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
