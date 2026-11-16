/** Scope the existing engine's root/theme WebSocket URLs to this preview only. */
(() => {
  const script = document.currentScript;
  const base = new URL("./", script.src);
  const port = Number(script.dataset.readerPreviewPort);
  const NativeSocket = window.WebSocket;
  window.WebSocket = class extends NativeSocket {
    constructor(value, protocols) {
      const url = new URL(value, location.href);
      const sameOrigin =
        url.host === base.host && ["ws:", "wss:", "http:", "https:"].includes(url.protocol);
      const registeredLoopback =
        ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) &&
        Number(url.port) === port &&
        ["ws:", "wss:"].includes(url.protocol);
      if (url.username || url.password || (!sameOrigin && !registeredLoopback))
        throw new DOMException("Preview socket is outside its registered origin", "SecurityError");
      url.protocol = base.protocol === "https:" ? "wss:" : "ws:";
      url.hostname = base.hostname;
      url.port = base.port;
      if (!url.pathname.startsWith(base.pathname))
        url.pathname = base.pathname + url.pathname.replace(/^\/+/, "");
      super(url.href, ...(protocols === undefined ? [] : [protocols]));
    }
  };
})();
