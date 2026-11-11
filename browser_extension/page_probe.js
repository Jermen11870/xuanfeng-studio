// 執行於網頁 MAIN world（頁面主環境），直接讀取 Suno 的 Clerk session
// 採用 Manifest V3 注入，避免觸發 Suno 嚴格的 CSP 阻擋
(() => {
  "use strict";

  const BRIDGE_SOURCE = "fengling-suno-login-helper";
  const BRIDGE_VERSION = 1;
  const REQUEST_KIND = "request-page-token";
  const RESPONSE_KIND = "page-token";
  const TOKEN_TIMEOUT_MS = 2500;
  let probeInFlight = false;
  let queuedRequestId = "";

  function withTimeout(promise, timeoutMs) {
    return Promise.race([
      Promise.resolve(promise),
      new Promise((resolve) => setTimeout(() => resolve(""), timeoutMs))
    ]);
  }

  async function emitPageToken(requestId) {
    if (probeInFlight) {
      queuedRequestId = requestId;
      return;
    }
    probeInFlight = true;

    let clerkToken = "";
    const clerkMeta = {
      clerk: !!window.Clerk,
      session: !!window.Clerk?.session,
      ts: Date.now()
    };

    try {
      const session = window.Clerk?.session;
      if (session && typeof session.getToken === "function") {
        const result = await withTimeout(session.getToken(), TOKEN_TIMEOUT_MS);
        clerkToken = typeof result === "string" ? result : "";
      }
      clerkMeta.len = clerkToken ? String(clerkToken).length : 0;
    } catch (error) {
      clerkMeta.error = true;
    }

    try {
      window.postMessage({
        source: BRIDGE_SOURCE,
        version: BRIDGE_VERSION,
        kind: RESPONSE_KIND,
        requestId,
        payload: {
          token: clerkToken,
          tokenSource: clerkToken ? "browser-extension-clerk" : "",
          tokenMeta: clerkMeta,
          href: location.href,
          ts: Date.now()
        }
      }, location.origin);
    } catch (_) {
      // 容錯降級
    } finally {
      probeInFlight = false;
      if (queuedRequestId) {
        const nextRequestId = queuedRequestId;
        queuedRequestId = "";
        setTimeout(() => { void emitPageToken(nextRequestId); }, 0);
      }
    }
  }

  // 監聽來自 ISOLATED world (content.js) 的訊息請求
  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    if (event.origin !== location.origin) return;
    const message = event.data;
    if (!message || message.source !== BRIDGE_SOURCE) return;
    if (message.version !== BRIDGE_VERSION || message.kind !== REQUEST_KIND) return;
    if (typeof message.requestId !== "string") return;
    void emitPageToken(message.requestId);
  });
})();
