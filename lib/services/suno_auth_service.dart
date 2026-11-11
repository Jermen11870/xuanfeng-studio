import 'dart:async';
import 'dart:convert';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import '../core/suno_constants.dart';
import '../models/suno_token.dart';
import 'suno_token_service.dart';

class SunoAuthService {
  final SunoTokenService tokenService;
  Webview? _webview;
  bool _isCapturing = false;
  Timer? _pollingTimer;

  SunoAuthService({required this.tokenService}) {
    tokenService.onTriggerSilentRefresh = silentRefreshToken;
  }

  bool get isLoginWindowOpen => _webview != null;

  /// JS 探針：精準抓取 Clerk JWT Token 及 ajs_anonymous_id
  static const String probeJs = '''
  (async function() {
    try {
      let token = '';
      let hasClerk = false;
      if (window.Clerk && window.Clerk.session && window.Clerk.session.getToken) {
        hasClerk = true;
        try {
          token = await window.Clerk.session.getToken() || '';
        } catch(err) {}
      }
      let deviceId = '';
      try {
        deviceId = localStorage.getItem('ajs_anonymous_id') || '';
      } catch(err) {}
      
      return JSON.stringify({
        hasClerk: hasClerk,
        token: token,
        deviceId: deviceId
      });
    } catch(e) {
      return JSON.stringify({ error: String(e) });
    }
  })();
  ''';

  /// 開啟原生 Suno 登入視窗並啟動自動抓取
  Future<void> openLoginWindow({bool silent = false}) async {
    if (_webview != null) {
      debugPrint('[SunoAuthService] 登入視窗已開啟。');
      return;
    }

    try {
      debugPrint('[SunoAuthService] 正在建立 WebviewWindow...');
      final webview = await WebviewWindow.create(
        configuration: const CreateConfiguration(
          windowWidth: 1120,
          windowHeight: 800,
          title: 'Suno 官方帳號登入 (旋風 studio)',
          titleBarTopPadding: 10,
        ),
      );

      _webview = webview;

      // 設定標準 User-Agent，避免被 Suno/Cloudflare 攔截
      await webview.setApplicationNameForUserAgent(
        ' Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
      );

      // 監聽網址跳轉日誌
      webview.setOnUrlRequestCallback((url) {
        debugPrint('[SunoAuthService] 網頁導航到: $url');
        return true;
      });

      // 監聽視窗關閉
      unawaited(webview.onClose.then((_) {
        debugPrint('[SunoAuthService] 登入視窗已被關閉。');
        _stopCapture();
        _webview = null;
      }));

      // 開啟 Suno 首頁
      debugPrint('[SunoAuthService] 開始載入 Suno 官網: ${SunoConstants.sunoHomeUrl}');
      webview.launch(SunoConstants.sunoHomeUrl);

      // 啟動輪詢探針
      _startCaptureLoop(silent: silent);
    } catch (e, stack) {
      debugPrint('[SunoAuthService] 建立 Webview 失敗: $e\n$stack');
    }
  }

  /// 啟動抓取循環（每 1.5 秒探測一次，直至抓到合規 Token）
  void _startCaptureLoop({bool silent = false}) {
    _stopCapture();
    _isCapturing = true;

    int attempts = 0;
    const maxAttempts = 300; // 最多探測 5 分鐘

    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      attempts++;
      if (!_isCapturing || _webview == null || attempts > maxAttempts) {
        _stopCapture();
        return;
      }

      try {
        // 1. 執行 JS 探針抓取 Clerk Session Token
        final jsResult = await _webview!.evaluateJavaScript(probeJs);
        if (jsResult != null && jsResult.isNotEmpty) {
          final data = _safeParseJson(jsResult);
          final rawToken = data['token'] as String? ?? '';
          final deviceId = data['deviceId'] as String? ?? '';

          if (rawToken.length >= 80) {
            final sunoToken = SunoToken.fromRawToken(
              rawToken,
              deviceId: deviceId,
              source: 'in-app-webview-clerk',
            );

            if (sunoToken.isValid) {
              debugPrint('[SunoAuthService] 成功抓取到有效 Clerk JWT Token！');
              await tokenService.updateToken(sunoToken);
              _stopCapture();
              closeLoginWindow();
              return;
            }
          }
        }

        // 2. 備援機制：讀取 HttpOnly Cookie 中的 __session
        final cookies = await _webview!.getAllCookies();
        for (final cookie in cookies) {
          if (cookie.name == '__session' && cookie.value.length >= 80) {
            final cookieToken = SunoToken.fromRawToken(
              cookie.value,
              source: 'in-app-webview-cookie',
            );
            if (cookieToken.isValid) {
              debugPrint('[SunoAuthService] 成功從 Cookie(__session) 抓取到 Token！');
              await tokenService.updateToken(cookieToken);
              _stopCapture();
              closeLoginWindow();
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('[SunoAuthService] 探針執行錯誤: $e');
      }
    });
  }

  void _stopCapture() {
    _isCapturing = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// 靜默刷新 Token
  Future<void> silentRefreshToken() async {
    debugPrint('[SunoAuthService] 執行靜默 Token 刷新...');
    if (_webview == null) {
      await openLoginWindow(silent: true);
    } else {
      _startCaptureLoop(silent: true);
    }
  }

  /// 關閉登入視窗
  void closeLoginWindow() {
    _stopCapture();
    try {
      _webview?.close();
    } catch (_) {}
    _webview = null;
  }

  Map<String, dynamic> _safeParseJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }
}
