import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/suno_token.dart';
import '../services/suno_token_service.dart';
import '../services/upload_history_service.dart';

class SunoMobileLoginScreen extends StatefulWidget {
  const SunoMobileLoginScreen({super.key});

  static Future<bool?> show(BuildContext context) {
    // 嚴格平台守衛：僅在原生 Android 與 iOS 上啟用內嵌 WebView，其餘環境自動調用預設瀏覽器
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      context.read<SunoTokenService>().openBrowserForLogin();
      return Future.value(false);
    }

    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SunoMobileLoginScreen(),
      ),
    );
  }

  @override
  State<SunoMobileLoginScreen> createState() => _SunoMobileLoginScreenState();
}

class _SunoMobileLoginScreenState extends State<SunoMobileLoginScreen> {
  WebViewController? _controller;
  WebViewCookieManager? _cookieManager;

  bool _isLoading = true;
  bool _isSuccess = false;
  String _statusText = '載入 Suno 登入頁面中...';
  Timer? _captureTimer;

  static const String _probeJs = '''
  (async function() {
    try {
      let token = '';
      let hasClerk = false;

      // 1. 優先嘗試 Clerk Session
      if (window.Clerk && window.Clerk.session && window.Clerk.session.getToken) {
        hasClerk = true;
        try {
          token = await window.Clerk.session.getToken() || '';
        } catch(err) {}
      }

      // 2. 備援：直接從 document.cookie 提取 __session
      if (!token) {
        try {
          const m = document.cookie.match(/__session=([^;]+)/);
          if (m && m[1]) {
            token = decodeURIComponent(m[1].trim());
          }
        } catch(err) {}
      }

      // 3. 備援：從 localStorage 掃描 JWT (eyJ...)
      if (!token) {
        try {
          for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            const val = localStorage.getItem(key) || '';
            const m = val.match(/eyJ[A-Za-z0-9_-]+(?:\\.[A-Za-z0-9_-]+){2}/);
            if (m && m[0]) {
              token = m[0];
              break;
            }
          }
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

  @override
  void initState() {
    super.initState();
    _initWebViewSafe();
  }

  void _initWebViewSafe() {
    // 安全檢測：若非 Android / iOS，不觸發 webview 初始化
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      _isLoading = false;
      _statusText = '當前環境不支援內嵌 WebView，請點擊右上角開啟瀏覽器登入。';
      return;
    }

    try {
      _cookieManager = WebViewCookieManager();

      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.6613.127 Mobile Safari/537.36',
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _statusText = '正在載入: ${Uri.tryParse(url)?.host ?? 'Suno'}';
                });
              }
            },
            onPageFinished: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _statusText = '請登入 Suno 帳戶（登入後自動截取 Token）';
                });
              }
              _checkTokenImmediate();
            },
          ),
        )
        ..loadRequest(Uri.parse('https://suno.com/login'));

      _startCaptureLoop();
    } catch (e) {
      debugPrint('[SunoMobileLogin] 初始化 WebView 異常: $e');
      setState(() {
        _isLoading = false;
        _statusText = 'WebView 初始化失敗，請切換至瀏覽器登入。';
      });
    }
  }

  void _startCaptureLoop() {
    _captureTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _checkTokenImmediate();
    });
  }

  Future<void> _checkTokenImmediate({bool isManual = false}) async {
    if (_isSuccess || !mounted || _controller == null) return;

    final tokenService = context.read<SunoTokenService>();

    try {
      // 1. JS 探針檢查 Clerk Session
      final jsResult = await _controller!.runJavaScriptReturningResult(_probeJs);
      final rawStr = jsResult.toString();

      String jsonText = rawStr;
      if (jsonText.startsWith('"') && jsonText.endsWith('"')) {
        try {
          jsonText = jsonDecode(jsonText) as String;
        } catch (_) {}
      }

      if (jsonText.contains('{')) {
        try {
          final data = jsonDecode(jsonText) as Map<String, dynamic>;
          final rawToken = data['token'] as String? ?? '';
          final deviceId = data['deviceId'] as String? ?? '';

          if (rawToken.length >= 80) {
            final sunoToken = SunoToken.fromRawToken(
              rawToken,
              deviceId: deviceId,
              source: 'mobile-webview-clerk',
            );
            if (sunoToken.isValid) {
              await _handleTokenSuccess(tokenService, sunoToken);
              return;
            }
          }
        } catch (_) {}
      }

      // 2. 備援：檢查 Cookie 中的 __session
      if (_cookieManager != null) {
        final candidateDomains = [
          Uri.parse('https://suno.com'),
          Uri.parse('https://clerk.suno.com'),
        ];
        for (final domainUri in candidateDomains) {
          final cookies = await _cookieManager!.getCookies(domain: domainUri);
          for (final cookie in cookies) {
            if (cookie.name == '__session' && cookie.value.length >= 80) {
              final cookieToken = SunoToken.fromRawToken(
                cookie.value,
                source: 'mobile-webview-cookie',
              );
              if (cookieToken.isValid) {
                await _handleTokenSuccess(tokenService, cookieToken);
                return;
              }
            }
          }
        }
      }

      if (isManual && !_isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('尚未檢測到登入憑證，請先在頁面輸入帳號密碼完成登入。'),
            backgroundColor: Color(0xFFE11D48),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[SunoMobileLogin] 探針檢測中: $e');
    }
  }

  Future<void> _handleTokenSuccess(SunoTokenService tokenService, SunoToken token) async {
    if (_isSuccess) return;
    _isSuccess = true;
    _captureTimer?.cancel();

    if (mounted) {
      setState(() {
        _statusText = '登入成功！已成功取得 Token！';
      });
    }

    await tokenService.updateToken(token);

    if (mounted) {
      try {
        context.read<UploadHistoryService>().syncFromSunoCloud(
              token: token.token,
              deviceId: token.deviceId,
            );
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Suno 登入成功！已自動保存 Token，日後無需重複登入。'),
          backgroundColor: Color(0xFF059669),
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Suno 帳戶登入',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              _statusText,
              style: TextStyle(
                color: _isSuccess ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_controller != null) ...[
            TextButton.icon(
              onPressed: () => _checkTokenImmediate(isManual: true),
              icon: const Icon(Icons.bolt, color: Color(0xFFFBBF24), size: 18),
              label: const Text(
                '提取 Token',
                style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              tooltip: '重新整理',
              onPressed: () => _controller!.reload(),
            ),
          ],
        ],
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  backgroundColor: Color(0xFF334155),
                  color: Color(0xFF02AF4A),
                ),
              )
            : null,
      ),
      body: _controller != null
          ? WebViewWidget(controller: _controller!)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.devices_other, size: 54, color: Color(0xFF64748B)),
                    const SizedBox(height: 16),
                    const Text(
                      '內嵌 WebView 僅支援 Android / iOS 手機原生 App',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '喺 Web 瀏覽器或電腦端測試時，請使用外部瀏覽器登入。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(false);
                        context.read<SunoTokenService>().openBrowserForLogin();
                      },
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('打開系統瀏覽器登入'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF02AF4A),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
