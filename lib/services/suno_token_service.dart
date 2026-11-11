import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/suno_constants.dart';
import '../models/suno_token.dart';

class SunoTokenService extends ChangeNotifier {
  static const String _prefTokenKey = 'suno_active_token_json';

  SunoToken? _token;
  bool _isLoading = false;
  final Set<String> _rejectedTokens = {};
  Timer? _countdownTimer;
  Timer? _autoRefreshTimer;
  Timer? _fileSyncTimer;
  HttpServer? _localServer;

  SunoToken? get currentToken => _token;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _token != null && _token!.isValid;

  // 定義回呼：當需要自動刷新 Token 時由 AuthService 執行
  Future<void> Function()? onTriggerSilentRefresh;

  SunoTokenService() {
    _loadSavedToken();
    _startCountdownTimer();
    if (!kIsWeb) {
      _startBrowserFileSync();
      _startLocalHttpServer();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _fileSyncTimer?.cancel();
    _localServer?.close(force: true);
    super.dispose();
  }

  /// 取得瀏覽器擴充同步檔案路徑
  String get _browserTokenFilePath {
    if (kIsWeb) return '';
    final home = Platform.environment['HOME'] ?? '';
    final newPath = '$home/Library/Application Support/旋風 studio/evidence/network/current_browser_token.json';
    if (File(newPath).existsSync()) return newPath;
    return '$home/Library/Application Support/风聆Studio/evidence/network/current_browser_token.json';
  }

  /// 開啟系統預設瀏覽器登入 Suno
  Future<void> openBrowserForLogin() async {
    try {
      debugPrint('[SunoTokenService] 正在調用系統瀏覽器打開 Suno...');
      final uri = Uri.parse('https://suno.com/login');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      // 同步檢查一次擴充檔案
      if (!kIsWeb) {
        await syncFromBrowserTokenFile();
      }
    } catch (e) {
      debugPrint('[SunoTokenService] 打開瀏覽器失敗: $e');
    }
  }

  /// 打開「風聆Studio 登錄助手」瀏覽器擴充套件資料夾
  Future<void> openExtensionFolder() async {
    if (kIsWeb) return;
    try {
      const candidates = [
        '/Users/jermen/Desktop/fengling_studio_flutter/browser_extension',
        'browser_extension',
      ];
      for (final p in candidates) {
        final dir = Directory(p);
        if (await dir.exists()) {
          await Process.run('open', [dir.path]);
          return;
        }
      }
      await Process.run('open', ['/Users/jermen/Desktop/fengling_studio_flutter/browser_extension']);
    } catch (e) {
      debugPrint('[SunoTokenService] 打開擴充套件資料夾失敗: $e');
    }
  }

  /// 定時監聽來自瀏覽器擴充套件寫入的 Token 檔案
  void _startBrowserFileSync() {
    if (kIsWeb) return;
    // 啟動先立即檢查一次
    syncFromBrowserTokenFile();

    // 每 3 秒檢查一次瀏覽器擴充是否送入最新 Token
    _fileSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      syncFromBrowserTokenFile();
    });
  }

  /// 從瀏覽器擴充套件（风聆Studio登录助手）的暫存檔同步 Token
  Future<bool> syncFromBrowserTokenFile() async {
    if (kIsWeb) return false;
    try {
      final file = File(_browserTokenFilePath);
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final Map<String, dynamic> data = jsonDecode(raw);
          final rawToken = data['token'] as String? ?? '';
          final deviceId = (data['deviceId'] as String? ?? '').replaceAll('"', '');
          final source = data['tokenSource'] as String? ?? 'browser-extension';

          if (rawToken.length >= 80 && (_token == null || _token!.token != rawToken)) {
            if (_rejectedTokens.contains(rawToken)) {
              return false;
            }
            final parsed = SunoToken.fromRawToken(rawToken, deviceId: deviceId, source: source);
            // 關鍵防護：如果檔案中的 Token 已過期，不予採用並清理無效快取檔
            if (parsed.isExpired) {
              try {
                await file.delete();
              } catch (_) {}
              return false;
            }

            // 若當前已有有效 Token，且檔案中的 Token 到期時間更早或相同，則不覆蓋
            if (_token != null && _token!.isValid && _token!.expiresAt != null && parsed.expiresAt != null) {
              if (!parsed.expiresAt!.isAfter(_token!.expiresAt!)) {
                return false;
              }
            }

            if (parsed.isValid) {
              debugPrint('[SunoTokenService] 成功從瀏覽器擴充同步到最新 Suno Token！');
              await updateToken(parsed);
              return true;
            }
          }
        }
      }
    } catch (e) {
      // 靜默容錯
    }
    return false;
  }

  /// 啟動本機 HTTP Server 接收擴充套件 POST http://127.0.0.1:23940/suno-token
  Future<void> _startLocalHttpServer({int port = 23940}) async {
    try {
      _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      debugPrint('[SunoTokenService] 本機 Token 接收伺服器已監聽: http://127.0.0.1:$port');
      _localServer!.listen((HttpRequest req) async {
        req.response.headers.add('Access-Control-Allow-Origin', '*');
        req.response.headers.add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
        req.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Origin, Authorization');

        if (req.method == 'OPTIONS') {
          req.response.statusCode = HttpStatus.ok;
          await req.response.close();
          return;
        }

        if (req.uri.path == '/suno-token' && req.method == 'POST') {
          final body = await utf8.decoder.bind(req).join();
          try {
            final data = jsonDecode(body);
            final tok = data['token'] as String? ?? '';
            final devId = (data['deviceId'] as String? ?? '').replaceAll('"', '');
            final src = data['tokenSource'] as String? ?? 'browser-extension-http';

            if (tok.length >= 80) {
              debugPrint('[SunoTokenService] 收到來自 $src 的 Token (${tok.length} 字元)，正在導入...');
              final parsed = SunoToken.fromRawToken(tok, deviceId: devId, source: src);
              await updateToken(parsed);
              req.response.headers.contentType = ContentType.json;
              req.response.write(jsonEncode({'ok': true, 'message': 'Token received'}));
            } else {
              req.response.statusCode = HttpStatus.badRequest;
              req.response.write(jsonEncode({'ok': false, 'message': 'Invalid token'}));
            }
          } catch (e) {
            req.response.statusCode = HttpStatus.badRequest;
          }
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });
    } catch (e) {
      // 若 23940 已被原版後台佔用，直接依賴檔案監聽器（完全無縫）
      debugPrint('[SunoTokenService] 本機 23940 端口已被佔用，自動啟用檔案無縫同步模式。');
    }
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_token != null) {
        notifyListeners();
      }
    });

    // 每 30 分鐘觸發一次靜默自動刷新
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (isLoggedIn && onTriggerSilentRefresh != null) {
        debugPrint('[SunoTokenService] 觸發 30 分鐘自動靜默保活刷新...');
        onTriggerSilentRefresh!();
      }
    });
  }

  Future<void> _loadSavedToken() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefTokenKey);
      if (raw != null && raw.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(raw);
        final loaded = SunoToken.fromJson(data);
        if (loaded.token.isNotEmpty && !loaded.isExpired) {
          _token = loaded;
          unawaited(validateTokenWithSuno());
        }
      }
    } catch (e) {
      debugPrint('[SunoTokenService] 載入保存 Token 失敗: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateToken(SunoToken token) async {
    _rejectedTokens.remove(token.token);
    _token = token;
    notifyListeners();

    // 立即持久化保存至本地快取
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefTokenKey, jsonEncode(token.toJson()));
    } catch (e) {
      debugPrint('[SunoTokenService] 寫入 Token 失敗: $e');
    }

    final isValid = await validateTokenWithSuno();
    if (!isValid) return;

    if (!kIsWeb) {
      try {
        final file = File(_browserTokenFilePath);
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }
        await file.writeAsString(jsonEncode({
          'token': token.token,
          'deviceId': token.deviceId,
          'tokenSource': token.source,
          'receivedAt': DateTime.now().millisecondsSinceEpoch,
        }));
      } catch (_) {}
    }
  }

  Future<void> clearToken() async {
    _token = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefTokenKey);
    } catch (e) {
      debugPrint('[SunoTokenService] 清除 Token 失敗: $e');
    }
  }

  /// 呼叫 Suno 官方 API 驗證 Token 是否有效
  Future<bool> validateTokenWithSuno() async {
    if (_token == null || _token!.token.isEmpty) return false;

    try {
      final url = Uri.parse('${SunoConstants.studioApiBase}/api/feed/v2?is_liked=false&limit=1&page=0');
      final headers = SunoConstants.buildHeaders(
        token: _token!.token,
        deviceId: _token!.deviceId,
      );

      final resp = await http.get(url, headers: headers).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        debugPrint('[SunoTokenService] Token 驗證成功！Suno API 通過。');
        return true;
      } else if (resp.statusCode == 401) {
        _rejectedTokens.add(_token!.token);
        debugPrint('[SunoTokenService] Suno API 401 Unauthorized：Token 已失效。');
        await clearToken();
        if (!kIsWeb) {
          try {
            final file = File(_browserTokenFilePath);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
        return false;
      }
    } catch (e) {
      debugPrint('[SunoTokenService] 驗證 Token 網絡請求異常: $e');
      if (kIsWeb) {
        return _token!.isValid;
      }
    }
    return false;
  }
}
