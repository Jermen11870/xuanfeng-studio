import 'dart:convert';

class SunoToken {
  final String token;
  final String deviceId;
  final String source;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final String? email;
  final int? creditsLeft;
  final String? subscriptionPlan;

  const SunoToken({
    required this.token,
    this.deviceId = '',
    this.source = 'in-app-webview',
    required this.updatedAt,
    this.expiresAt,
    this.email,
    this.creditsLeft,
    this.subscriptionPlan,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return expiresAt!.isBefore(DateTime.now());
  }

  bool get isValid => token.trim().isNotEmpty && !isExpired;

  int get remainingSeconds {
    if (expiresAt == null) return 0;
    final diff = expiresAt!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  static DateTime? parseJwtExpiration(String jwtToken) {
    try {
      final parts = jwtToken.split('.');
      if (parts.length < 2) return null;
      var normalized = base64Url.normalize(parts[1]);
      final payloadStr = utf8.decode(base64Url.decode(normalized));
      final Map<String, dynamic> payload = jsonDecode(payloadStr);
      final exp = payload['exp'];
      if (exp is int) {
        return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      }
    } catch (_) {}
    return null;
  }

  static String extractCleanToken(String input) {
    var raw = input.trim();
    // 優先：正則直接匹配 Clerk JWT 標準三段結構 (eyJ...)
    final jwtMatch = RegExp(r'eyJ[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+){2}').firstMatch(raw);
    if (jwtMatch != null) {
      return jwtMatch.group(0)!;
    }

    // 若未精確匹配三段，若含有 eyJ 則截取
    final eyjIdx = raw.indexOf('eyJ');
    if (eyjIdx != -1) {
      raw = raw.substring(eyjIdx);
      final stopIdx = raw.indexOf(RegExp(r'[\s";]'));
      if (stopIdx != -1) {
        raw = raw.substring(0, stopIdx);
      }
    }

    if (raw.startsWith('Bearer ')) {
      raw = raw.substring(7).trim();
    }
    if (raw.contains('__session=')) {
      final parts = raw.split(';');
      for (final p in parts) {
        final idx = p.indexOf('=');
        if (idx != -1) {
          final k = p.substring(0, idx).trim();
          final v = p.substring(idx + 1).trim();
          if (k == '__session' || k.endsWith('__session')) {
            raw = v;
            break;
          }
        }
      }
    }
    raw = raw.replaceAll('"', '').replaceAll("'", '');
    // 嚴格消毒：任何 Token/JWT 必須是純 ASCII，過濾掉所有中文與 non ISO-8859-1 字符
    return raw.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  }

  factory SunoToken.fromRawToken(String token, {String deviceId = '', String source = 'in-app-webview'}) {
    final clean = extractCleanToken(token);
    final exp = parseJwtExpiration(clean);
    return SunoToken(
      token: clean,
      deviceId: deviceId,
      source: source,
      updatedAt: DateTime.now(),
      expiresAt: exp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'deviceId': deviceId,
      'source': source,
      'updatedAt': updatedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'email': email,
      'creditsLeft': creditsLeft,
      'subscriptionPlan': subscriptionPlan,
    };
  }

  factory SunoToken.fromJson(Map<String, dynamic> json) {
    return SunoToken(
      token: json['token'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      source: json['source'] as String? ?? 'in-app-webview',
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      email: json['email'] as String?,
      creditsLeft: json['creditsLeft'] as int?,
      subscriptionPlan: json['subscriptionPlan'] as String?,
    );
  }

  SunoToken copyWith({
    String? token,
    String? deviceId,
    String? source,
    DateTime? updatedAt,
    DateTime? expiresAt,
    String? email,
    int? creditsLeft,
    String? subscriptionPlan,
  }) {
    return SunoToken(
      token: token ?? this.token,
      deviceId: deviceId ?? this.deviceId,
      source: source ?? this.source,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      email: email ?? this.email,
      creditsLeft: creditsLeft ?? this.creditsLeft,
      subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
    );
  }
}
