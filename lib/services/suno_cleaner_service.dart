import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/suno_constants.dart';
import 'suno_token_service.dart';
import 'upload_history_service.dart';

class SunoSliceItem {
  final String clipId;
  final String title;
  final String createdAt;
  final String? audioUrl;
  final double? durationSec;

  SunoSliceItem({
    required this.clipId,
    required this.title,
    required this.createdAt,
    this.audioUrl,
    this.durationSec,
  });
}

class SunoCleanerService extends ChangeNotifier {
  final SunoTokenService tokenService;
  final UploadHistoryService historyService;

  bool _isScanning = false;
  bool _isCleaning = false;
  List<SunoSliceItem> _detectedSlices = [];
  String _statusMessage = '';

  SunoCleanerService({required this.tokenService, required this.historyService});

  bool get isScanning => _isScanning;
  bool get isCleaning => _isCleaning;
  List<SunoSliceItem> get detectedSlices => List.unmodifiable(_detectedSlices);
  String get statusMessage => _statusMessage;

  /// 判斷一個 clip 是否為 4X 切片或臨時中間碎片
  static bool isSliceClip(Map<String, dynamic> clip) {
    if (clip['is_trashed'] == true) return false;
    final title = (clip['title'] as String? ?? '').trim().toLowerCase();
    final metadata = clip['metadata'] as Map<String, dynamic>? ?? {};
    final type = metadata['type'] as String? ?? '';

    // 切片命名正規規則
    final isSlicePattern = RegExp(r'^(slice|seg|carrier_shard|part|uploaded_part)[\d_]', caseSensitive: false).hasMatch(title) ||
                           title.contains('preproc_spd') ||
                           title.contains('slice_') ||
                           title.endsWith('.wav');

    // 只要是 upload 類型且命中切片特徵，即判定為切片素材
    return (type == 'upload' || type.isEmpty) && isSlicePattern;
  }

  /// 掃描 Suno 線上的歌曲切片碎片
  Future<List<SunoSliceItem>> scanForSlices({int maxPages = 5}) async {
    final token = tokenService.currentToken;
    if (token == null || token.token.isEmpty) {
      _statusMessage = '請先登入 Suno';
      notifyListeners();
      return [];
    }

    _isScanning = true;
    _statusMessage = '正在掃描 Suno 作品庫中的切片素材...';
    _detectedSlices.clear();
    notifyListeners();

    // 收集所有需要保護的完整歌曲 ID（絕不刪除完整作品）
    final protectedIds = <String>{};
    for (final it in historyService.items) {
      if (it.renderId != null && it.renderId!.isNotEmpty) {
        protectedIds.add(it.renderId!);
      }
      if (it.clipId != null && it.clipId!.isNotEmpty && it.uploadMode != 'slice') {
        protectedIds.add(it.clipId!);
      }
    }

    final headers = SunoConstants.buildHeaders(token: token.token, deviceId: token.deviceId);
    final List<SunoSliceItem> found = [];
    final seen = <String>{};

    try {
      for (int page = 0; page < maxPages; page++) {
        _statusMessage = '正在檢索第 \${page + 1} 頁作品記錄...';
        notifyListeners();

        final url = Uri.parse('\${SunoConstants.studioApiBase}/api/feed/v2?is_liked=false&limit=30&page=\$page');
        final resp = await http.get(url, headers: headers).timeout(const Duration(seconds: 20));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final clips = (data['clips'] as List?) ?? [];

          for (final c in clips) {
            if (c is! Map<String, dynamic>) continue;
            final id = (c['id'] as String? ?? '').trim();
            if (id.isEmpty || seen.contains(id) || protectedIds.contains(id)) continue;

            if (isSliceClip(c)) {
              seen.add(id);
              found.add(
                SunoSliceItem(
                  clipId: id,
                  title: c['title'] as String? ?? '未命名切片',
                  createdAt: (c['created_at'] as String? ?? '').split('.')[0],
                  audioUrl: c['audio_url'] as String?,
                  durationSec: (c['duration'] as num?)?.toDouble(),
                ),
              );
            }
          }

          final hasMore = data['has_more'] as bool? ?? false;
          if (!hasMore || clips.isEmpty) break;
        } else {
          break;
        }
      }

      _detectedSlices = found;
      _statusMessage = '掃描完成：共發現 \${found.length} 個歌曲切片碎片（已保護所有完整成品歌曲）';
    } catch (e) {
      _statusMessage = '掃描出錯: \$e';
      debugPrint('[SunoCleanerService] 掃描切片失敗: \$e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }

    return _detectedSlices;
  }

  /// 執行清理碎片（移入 Suno 回收站）
  Future<int> trashSlices(List<String> clipIds) async {
    final token = tokenService.currentToken;
    if (token == null || token.token.isEmpty || clipIds.isEmpty) return 0;

    _isCleaning = true;
    _statusMessage = '正在將 \${clipIds.length} 個切片碎片移入回收站...';
    notifyListeners();

    int successCount = 0;
    const batchSize = 20;

    try {
      final url = Uri.parse('\${SunoConstants.studioApiBase}/api/gen/trash');
      final headers = SunoConstants.buildHeaders(token: token.token, deviceId: token.deviceId);
      headers['Content-Type'] = 'application/json';

      for (int i = 0; i < clipIds.length; i += batchSize) {
        final end = (i + batchSize < clipIds.length) ? i + batchSize : clipIds.length;
        final batch = clipIds.sublist(i, end);

        _statusMessage = '正在清理第 \${i + 1} 至 \$end 個碎片...';
        notifyListeners();

        final body = jsonEncode({
          'trash': true,
          'clip_ids': batch,
        });

        try {
          final resp = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 40));
          if (resp.statusCode == 200 || resp.statusCode == 204) {
            successCount += batch.length;
          } else {
            // 單個重試
            for (final cid in batch) {
              final singleBody = jsonEncode({'trash': true, 'clip_ids': [cid]});
              final sResp = await http.post(url, headers: headers, body: singleBody);
              if (sResp.statusCode == 200 || sResp.statusCode == 204 || sResp.statusCode == 404) {
                successCount++;
              }
            }
          }
        } catch (_) {}
      }

      // 從本地掃描清單移除已清理項目
      _detectedSlices.removeWhere((it) => clipIds.contains(it.clipId));
      _statusMessage = '✓ 成功清理 \$successCount 個歌曲切片！Suno 作品庫已恢復整潔。';
    } catch (e) {
      _statusMessage = '清理過程中發生異常: \$e';
    } finally {
      _isCleaning = false;
      notifyListeners();
    }

    return successCount;
  }
}
