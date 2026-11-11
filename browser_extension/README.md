# 旋風 studio 登錄助手 (Chrome / Edge 瀏覽器擴充功能)

本擴充功能專為配合「旋風 studio」桌面端設計，當你喺瀏覽器打開並登入 Suno (https://suno.com) 時，擴充功能會自動將最新嘅登入 Session 憑證無縫傳回旋風 studio，免除手動複製貼上 Token 嘅繁瑣步驟。

---

## 🚀 30 秒安裝指南

1. **開啟擴充功能管理頁**：
   - **Google Chrome**：喺網址列輸入 `chrome://extensions/` 並 Enter
   - **Microsoft Edge**：喺網址列輸入 `edge://extensions/` 並 Enter
   - **Brave / Arc**：亦支援直接載入 Chromium 擴充

2. **開啟「開發者模式」**：
   - 喺管理頁右上角（或左下角），將「**開發人員模式 / Developer mode**」開關打開。

3. **載入擴充套件**：
   - 點擊左上方嘅「**載入未封裝項目 / Load unpacked**」按鈕。
   - 喺彈出嘅檔案選擇視窗中，選取本資料夾（或解壓後的擴充功能資料夾，確認裡面有 `manifest.json`）。

4. **登入 Suno 並完成同步**：
   - 喺同一個瀏覽器開啟 https://suno.com/ 並登入帳號。
   - 擴充功能會喺背景自動同步；你亦可以隨時點擊瀏覽器工具列嘅「旋風 studio 登錄助手」圖標，撳「⚡ 即刻同步至旋風 studio」手動觸發。
   - 返到旋風 studio，即刻見到憑證已經就緒！

---

## ⚙️ 運作原理
- **MAIN World 探針**：透過 `page_probe.js` 安全提取 Suno 網頁 Clerk Session，100% 避開 CSP 限制。
- **本機雙向通道**：直接向本地 `http://127.0.0.1:23940/suno-token` 發送 POST 請求，毫秒級同步。
