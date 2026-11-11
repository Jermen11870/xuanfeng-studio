import 'dart:convert';
import 'package:flutter/foundation.dart';

class SunoConstants {
  static const String studioApiBase = 'https://studio-api-prod.suno.com';
  static const String sunoHomeUrl = 'https://suno.com/';
  static const String sunoStudioUrl = 'https://suno.com/studio';

  static const String defaultUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36';

  /// 對齊 Suno 規範：Browser-Token = JSON{"token": base64(JSON{"timestamp": now_ms})}
  static String generateBrowserToken() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final innerJson = jsonEncode({'timestamp': nowMs});
    final base64String = base64Encode(utf8.encode(innerJson));
    return jsonEncode({'token': base64String});
  }

  /// 取得標準 Suno 請求 Headers
  static Map<String, String> buildHeaders({
    required String token,
    String? deviceId,
  }) {
    // 嚴格消毒：確保 Headers 所有字符皆為標準 ASCII 字符，避免瀏覽器 fetch 拋出 non ISO-8859-1 例外
    final cleanToken = token.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    final cleanDeviceId = (deviceId ?? '').replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();

    final headers = <String, String>{
      'Authorization': 'Bearer $cleanToken',
      'Accept': 'application/json, text/plain, */*',
    };

    // 瀏覽器環境下 Origin, Referer, User-Agent 屬於 Forbidden Headers，手動設置會觸發 CORS preflight 攔截
    if (!kIsWeb) {
      headers['Browser-Token'] = generateBrowserToken();
      headers['Origin'] = 'https://suno.com';
      headers['Referer'] = 'https://suno.com/studio';
      headers['User-Agent'] = defaultUserAgent;
    }

    if (cleanDeviceId.isNotEmpty) {
      headers['Device-Id'] = cleanDeviceId;
    }

    return headers;
  }
}
