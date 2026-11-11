// 旋風 studio 登錄助手 - 內容腳本 (ISOLATED world)
// 安全、無靜默報錯，自動對接本機 Flutter 服務 http://127.0.0.1:23940/suno-token

const DEV_ENDPOINT = "http://127.0.0.1:23940/suno-token";
const EXTENSION_VERSION = "1.0.0";
const PAGE_BRIDGE_SOURCE = "fengling-suno-login-helper";
const PAGE_BRIDGE_VERSION = 1;
const PAGE_REQUEST_KIND = "request-page-token";
const PAGE_RESPONSE_KIND = "page-token";

let lastToken = "";
let lastSentAt = 0;
let activeProbeRequestId = "";
let probeRetryTimers = [];
let activeProbePromise = null;
let resolveActiveProbe = null;
const sendQueue = [];
let currentSendJob = null;
let sendRunner = null;

function isLikelyJwt(value) {
  return typeof value === "string"
    && value.length >= 80
    && value.length <= 8192
    && /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value);
}

function readCookieToken() {
  let items = [];
  try {
    items = String(document.cookie || "").split(/;\s*/).filter(Boolean);
  } catch (_) {
    return "";
  }
  for (const item of items) {
    const idx = item.indexOf("=");
    if (idx <= 0) continue;
    const name = item.slice(0, idx);
    if (!(name === "__session" || name.startsWith("__session"))) continue;
    try {
      const value = decodeURIComponent(item.slice(idx + 1));
      if (value) return value;
    } catch (_) {}
  }
  return "";
}

function readLocalPayload() {
  let deviceId = "";
  try {
    deviceId = localStorage.getItem("ajs_anonymous_id") || "";
  } catch (_) {}
  return { deviceId, href: location.href, ts: Date.now() };
}

function injectPageProbe() {
  if (activeProbePromise) return activeProbePromise;
  activeProbeRequestId = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
  activeProbePromise = new Promise((resolve) => { resolveActiveProbe = resolve; });

  for (const delay of [600, 1500, 2600]) {
    probeRetryTimers.push(setTimeout(() => postPageProbeRequest(activeProbeRequestId), delay));
  }
  probeRetryTimers.push(setTimeout(() => finishPageProbe({}), 5000));
  postPageProbeRequest(activeProbeRequestId);
  return activeProbePromise;
}

function postPageProbeRequest(requestId) {
  if (!requestId) return;
  try {
    window.postMessage({
      source: PAGE_BRIDGE_SOURCE,
      version: PAGE_BRIDGE_VERSION,
      kind: PAGE_REQUEST_KIND,
      requestId
    }, location.origin);
  } catch (_) {}
}

function finishPageProbe(payload) {
  const resolve = resolveActiveProbe;
  for (const timer of probeRetryTimers) clearTimeout(timer);
  probeRetryTimers = [];
  activeProbeRequestId = "";
  activeProbePromise = null;
  resolveActiveProbe = null;
  if (resolve) {
    try { resolve(payload || {}); } catch (_) {}
  }
}

function normalizePagePayload(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const token = value.token;
  if (typeof token !== "string") return null;
  if (token && !isLikelyJwt(token)) return null;
  const ts = Number(value.ts);
  if (!Number.isFinite(ts) || Math.abs(Date.now() - ts) > 60000) return null;
  const meta = value.tokenMeta;
  return {
    token,
    tokenSource: token ? "browser-extension-clerk" : "",
    tokenMeta: {
      clerk: !!(meta && typeof meta === "object" && meta.clerk),
      session: !!(meta && typeof meta === "object" && meta.session),
      len: token.length,
      ts
    }
  };
}

window.addEventListener("message", (event) => {
  if (event.source !== window) return;
  if (event.origin !== location.origin) return;
  if (!event.data || event.data.source !== PAGE_BRIDGE_SOURCE) return;
  if (event.data.version !== PAGE_BRIDGE_VERSION) return;
  if (event.data.kind !== PAGE_RESPONSE_KIND) return;
  if (!event.data.requestId || event.data.requestId !== activeProbeRequestId) return;
  const payload = normalizePagePayload(event.data.payload);
  if (!payload) return;
  if (payload.token) {
    finishPageProbe(payload);
  }
});

async function sendLoginState(force) {
  try {
    if (!location.hostname.endsWith("suno.com")) return { ok: false, reason: "not-suno" };
    const localPayload = readLocalPayload();
    // 優先由 MAIN world 探針向 Clerk 獲取全新即時 JWT
    const probedPayload = await injectPageProbe();
    const clerkToken = (probedPayload && probedPayload.token) || "";
    const cookieToken = readCookieToken();

    let token = clerkToken;
    let tokenSource = "browser-extension-clerk";

    // 若探針未能取到，且 Cookie 為合法未過期的 JWT 才作為備援
    if (!token && cookieToken && isLikelyJwt(cookieToken)) {
      try {
        const parts = cookieToken.split(".");
        const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
        const jsonPayload = decodeURIComponent(atob(b64).split("").map(c => "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2)).join(""));
        const data = JSON.parse(jsonPayload);
        if (data.exp && data.exp * 1000 > Date.now() + 30000) {
          token = cookieToken;
          tokenSource = "browser-extension-cookie";
        }
      } catch (_) {}
    }

    if (!token) {
      return { ok: false, reason: "no-token" };
    }

    const now = Date.now();
    if (!force && token === lastToken && now - lastSentAt < 10000) {
      return { ok: true, reason: "throttled" };
    }

    const payload = {
      token,
      tokenSource: tokenSource,
      deviceId: localPayload.deviceId,
      href: localPayload.href,
      ts: now,
      extension: "fengling-suno-login-helper",
      extensionVersion: EXTENSION_VERSION,
      manual: !!force
    };

    const controller = new AbortController();
    const fetchTimeout = setTimeout(() => controller.abort(), 3500);
    let res = null;
    try {
      res = await fetch(DEV_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: controller.signal
      });
    } finally {
      clearTimeout(fetchTimeout);
    }

    if (res && res.ok) {
      lastToken = token;
      lastSentAt = now;
      return { ok: true, reason: "sent" };
    }
    return { ok: false, reason: "send-failed" };
  } catch (_) {
    return { ok: false, reason: "send-failed" };
  }
}

function safeSendLoginState(force) {
  try {
    return new Promise((resolve) => {
      let job = null;
      if (force) {
        if (currentSendJob && currentSendJob.force) job = currentSendJob;
        if (!job) job = sendQueue.find((item) => item.force) || null;
      } else {
        job = currentSendJob || sendQueue[0] || null;
      }
      if (!job) {
        job = { force: !!force, waiters: [] };
        sendQueue.push(job);
      }
      job.waiters.push(resolve);
      runSendQueue();
    });
  } catch (_) {
    return Promise.resolve({ ok: false, reason: "error" });
  }
}

function runSendQueue() {
  if (sendRunner) return sendRunner;
  sendRunner = (async () => {
    while (sendQueue.length) {
      const job = sendQueue.shift();
      currentSendJob = job;
      let result = { ok: false, reason: "error" };
      try {
        result = await sendLoginState(job.force);
      } catch (_) {}
      currentSendJob = null;
      for (const resolve of job.waiters.splice(0)) {
        try { resolve(result); } catch (_) {}
      }
    }
  })().catch(() => {}).finally(() => {
    currentSendJob = null;
    sendRunner = null;
    if (sendQueue.length) runSendQueue();
  });
  return sendRunner;
}

// 監聽來自 Extension Popup 的手動同步請求
try {
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message && message.type === "SUNO_DEV_SEND_LOGIN") {
      safeSendLoginState(true).then((result) => {
        try {
          sendResponse({ ok: !!(result && result.ok), reason: (result && result.reason) || "" });
        } catch (_) {}
      });
      return true;
    }
    return false;
  });
} catch (_) {}

// 自動排程與頁面活動監聽
safeSendLoginState(false);
setInterval(() => {
  safeSendLoginState(false);
}, 12000);
window.addEventListener("focus", () => safeSendLoginState(true));
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) safeSendLoginState(true);
});
