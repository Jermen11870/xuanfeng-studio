const statusTitleEl = document.getElementById("statusTitle");
const statusDescEl = document.getElementById("statusDesc");
const dotEl = document.getElementById("dot");
const sendBtn = document.getElementById("sendBtn");

function setStatus(title, desc, tone) {
  if (statusTitleEl) statusTitleEl.textContent = title;
  if (statusDescEl) statusDescEl.textContent = desc;
  if (dotEl) {
    dotEl.className = "dot " + (tone || "");
  }
}

async function checkStatus() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    const isSuno = tab && tab.url && (tab.url.includes("suno.com") || tab.url.includes("suno.ai"));

    if (!isSuno) {
      setStatus("未在 Suno 頁面", "請切換至已開啟的 suno.com 標籤頁或點擊下方鏈接登入。", "warn");
      return;
    }

    setStatus("Suno 頁面已就緒", "點擊下方按鈕即可提取最新登入憑證並同步。", "ok");
  } catch (e) {
    setStatus("狀態檢查異常", String(e.message || e), "err");
  }
}

sendBtn.addEventListener("click", async () => {
  sendBtn.disabled = true;
  setStatus("正在提取憑證...", "正在呼叫 Clerk Session 提取最新 Token...", "warn");

  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab || !tab.id || !tab.url || !tab.url.includes("suno.com")) {
      setStatus("請先切換至 Suno", "目前標籤頁並非 suno.com，無法提取登入 Token。", "warn");
      sendBtn.disabled = false;
      return;
    }

    let token = "";
    let deviceId = "";
    let userEmail = "";
    let diag = "";

    // 途徑 1：透過 chrome.scripting 直接在頁面 MAIN world 調用 Clerk.session.getToken()
    try {
      if (chrome.scripting) {
        const results = await chrome.scripting.executeScript({
          target: { tabId: tab.id },
          world: "MAIN",
          func: async () => {
            try {
              let tok = "";
              let dev = "";
              let email = "";
              try { dev = localStorage.getItem("ajs_anonymous_id") || ""; } catch (_) {}

              if (window.Clerk && window.Clerk.session && typeof window.Clerk.session.getToken === "function") {
                tok = await window.Clerk.session.getToken();
                if (window.Clerk.user) {
                  email = window.Clerk.user.primaryEmailAddress?.emailAddress || window.Clerk.user.username || "";
                }
                return { ok: true, token: tok, deviceId: dev, email: email };
              }

              // 檢查是否有全域 Session 物件
              return {
                ok: false,
                hasClerk: !!window.Clerk,
                hasSession: !!window.Clerk?.session,
                hasUser: !!window.Clerk?.user
              };
            } catch (err) {
              return { ok: false, error: String(err) };
            }
          }
        });

        if (results && results[0] && results[0].result) {
          const res = results[0].result;
          if (res.ok && res.token && res.token.length >= 80) {
            token = res.token;
            deviceId = res.deviceId || "";
            userEmail = res.email || "";
          } else {
            diag = `clerk:${res.hasClerk}, session:${res.hasSession}, user:${res.hasUser}`;
          }
        }
      }
    } catch (e) {
      diag = `scripting error: ${e.message}`;
    }

    // 途徑 2：若途徑 1 未取到，使用 chrome.cookies 讀取 HttpOnly __session Cookie
    if (!token && chrome.cookies) {
      try {
        const cookie = await chrome.cookies.get({ url: "https://suno.com", name: "__session" });
        if (cookie && cookie.value && cookie.value.length >= 80) {
          token = cookie.value;
        }
      } catch (_) {}
    }

    // 途徑 3：若仍未取到，嘗試向 content script 發送訊息
    if (!token) {
      try {
        const res = await chrome.tabs.sendMessage(tab.id, { type: "SUNO_DEV_SEND_LOGIN" });
        if (res && res.ok) {
          setStatus("同步成功！", "Suno 憑證已成功傳入旋風 studio，請切換回 App 查看。", "ok");
          sendBtn.disabled = false;
          return;
        }
      } catch (_) {}
    }

    // 驗證是否成功取得有效 Token
    if (!token || token.length < 80) {
      setStatus("未取得有效登入", `請先確認在 Suno 網頁完全載入並登入帳號 (${diag || "未檢測到 Clerk"})。`, "warn");
      sendBtn.disabled = false;
      return;
    }

    // 直接發送至本機 Flutter 服務 http://127.0.0.1:23940/suno-token
    setStatus("正在傳送至 App...", "已成功提取 Token，正在寫入旋風 studio...", "warn");
    const payload = {
      token: token,
      deviceId: deviceId,
      tokenSource: "browser-extension-direct",
      user: userEmail,
      ts: Date.now()
    };

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 4000);
    try {
      const resp = await fetch("http://127.0.0.1:23940/suno-token", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: controller.signal
      });
      clearTimeout(timeout);

      if (resp.ok) {
        setStatus("同步成功！", `憑證已成功傳入旋風 studio！${userEmail ? `(${userEmail})` : ""}`, "ok");
      } else {
        setStatus("App 接收失敗", "旋風 studio 本機服務回應錯誤，請確認 App 正常運行。", "err");
      }
    } catch (err) {
      clearTimeout(timeout);
      setStatus("連線失敗", "未能連接旋風 studio 本地端口 23940，請確認 App 正在運行。", "err");
    }
  } catch (err) {
    setStatus("同步異常", String(err.message || err), "err");
  } finally {
    sendBtn.disabled = false;
  }
});

checkStatus();
