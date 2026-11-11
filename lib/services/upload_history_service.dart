import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/suno_constants.dart';
import '../models/upload_history_item.dart';

class UploadHistoryService extends ChangeNotifier {
  List<UploadHistoryItem> _items = [];
  bool _isLoading = false;
  bool _isSyncingCloud = false;
  String _searchKeyword = '';

  List<UploadHistoryItem> get items {
    if (_searchKeyword.trim().isEmpty) {
      return List.unmodifiable(_items);
    }
    final kw = _searchKeyword.toLowerCase();
    return _items.where((it) {
      return it.title.toLowerCase().contains(kw) ||
          it.lyrics.toLowerCase().contains(kw) ||
          (it.clipId?.toLowerCase().contains(kw) ?? false) ||
          (it.renderId?.toLowerCase().contains(kw) ?? false);
    }).toList();
  }

  bool get isLoading => _isLoading;
  bool get isSyncingCloud => _isSyncingCloud;
  String get searchKeyword => _searchKeyword;

  UploadHistoryService() {
    loadHistory();
  }

  /// 跨平台歷史記錄保存路徑
  Future<String> _getHistoryFilePath() async {
    if (!kIsWeb && Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      final newPath = '$home/Library/Application Support/旋風 studio/upload_history.json';
      final oldPath = '$home/Library/Application Support/风聆Studio/upload_history.json';
      if (await File(newPath).exists()) return newPath;
      if (await File(oldPath).exists()) return oldPath;
      return newPath;
    }
    // 手機 Android / iOS 採用文檔目錄，永久持久化保存
    try {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/upload_history.json';
    } catch (_) {
      return '${Directory.systemTemp.path}/xuanfeng_upload_history.json';
    }
  }

  void setSearchKeyword(String kw) {
    _searchKeyword = kw;
    notifyListeners();
  }

  /// 載入歷史記錄
  Future<void> loadHistory() async {
    _isLoading = true;
    notifyListeners();

    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final content = prefs.getString('xuanfeng_upload_history_json');
        if (content != null && content.isNotEmpty) {
          final dynamic decoded = jsonDecode(content);
          if (decoded is List) {
            _items = decoded.map((e) => UploadHistoryItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
            _items.sort((a, b) => b.time.compareTo(a.time));
          }
        }
      } catch (e) {
        debugPrint('[UploadHistoryService] Web 載入歷史失敗: $e');
      } finally {
        _isLoading = false;
        notifyListeners();
      }
      return;
    }

    try {
      final path = await _getHistoryFilePath();
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final dynamic decoded = jsonDecode(content);
        if (decoded is List) {
          _items = decoded.map((e) => UploadHistoryItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          // 最新在最前面
          _items.sort((a, b) => b.time.compareTo(a.time));
        }
      }
    } catch (e) {
      debugPrint('[UploadHistoryService] 載入歷史失敗: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 嚴格過濾切片碎片演算法（絕不混雜 4X 變速中間片段）
  static bool isSliceClip(Map<String, dynamic> clip) {
    if (clip['is_trashed'] == true) return false;
    final title = (clip['title'] as String? ?? '').trim().toLowerCase();
    final metadata = clip['metadata'] as Map<String, dynamic>? ?? {};
    final type = metadata['type'] as String? ?? '';
    final duration = (clip['duration'] as num?)?.toDouble() ?? 0.0;

    // 切片命名正規規則
    final isSlicePattern = RegExp(r'^(slice|seg|carrier_shard|part|uploaded_part)[\d_]', caseSensitive: false).hasMatch(title) ||
        title.contains('preproc_spd') ||
        title.contains('slice_') ||
        title.endsWith('.wav');

    if ((type == 'upload' || type.isEmpty) && isSlicePattern) return true;
    // 凡時長小於等於 15 秒且名字帶切片/音訊後綴者均視為碎片
    if (duration > 0 && duration <= 15.0 && (title.startsWith('slice') || title.contains('.wav') || title.contains('seg'))) {
      return true;
    }
    return false;
  }

  /// 從 Suno 官方雲端拉取歷史作品（自動過濾碎片，只保留合成成曲）
  Future<int> syncFromSunoCloud({
    required String token,
    String? deviceId,
    int maxPages = 5,
  }) async {
    if (token.isEmpty || _isSyncingCloud) return 0;

    _isSyncingCloud = true;
    notifyListeners();

    int addedOrUpdatedCount = 0;
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);

    try {
      final existingClipMap = <String, UploadHistoryItem>{};
      for (final item in _items) {
        if (item.clipId != null && item.clipId!.isNotEmpty) {
          existingClipMap[item.clipId!] = item;
        }
        if (item.renderId != null && item.renderId!.isNotEmpty) {
          existingClipMap[item.renderId!] = item;
        }
      }

      final List<UploadHistoryItem> newFetchedItems = [];

      // 1. 同時查詢用戶的所有音訊上傳清單 (api/uploads/audio/)
      try {
        final uploadsUrl = Uri.parse('${SunoConstants.studioApiBase}/api/uploads/audio/');
        final uResp = await http.get(uploadsUrl, headers: headers).timeout(const Duration(seconds: 15));
        if (uResp.statusCode == 200) {
          final dynamic uData = jsonDecode(uResp.body);
          final List uploadList = uData is List ? uData : ((uData is Map && uData['uploads'] is List) ? uData['uploads'] : []);
          for (final u in uploadList) {
            if (u is! Map<String, dynamic>) continue;
            final uId = (u['id'] as String? ?? '').trim();
            if (uId.isEmpty) continue;
            final uTitle = (u['title'] as String? ?? u['upload_filename'] as String? ?? '').trim();
            if (isSliceClip(u)) continue;

            final targetClipId = (u['clip_id'] as String? ?? uId).trim();
            if (!existingClipMap.containsKey(uId) && !existingClipMap.containsKey(targetClipId)) {
              final item = UploadHistoryItem(
                id: 'upload_$uId',
                title: uTitle.isNotEmpty ? uTitle : '上傳音訊 ($uId)',
                lyrics: (u['prompt'] as String? ?? '').trim(),
                status: (u['status'] as String? ?? 'complete'),
                time: (u['created_at'] as String? ?? '').split('.')[0].replaceAll('T', ' '),
                clipId: targetClipId,
                renderId: uId,
                songUrl: 'https://suno.com/song/$targetClipId',
                audioUrl: u['audio_url'] as String?,
                uploadMode: 'audioUpload',
              );
              newFetchedItems.add(item);
              existingClipMap[uId] = item;
              existingClipMap[targetClipId] = item;
              addedOrUpdatedCount++;
            }
          }
        }
      } catch (err) {
        debugPrint('[UploadHistoryService] 獲取 api/uploads/audio/ 失敗: $err');
      }

      // 2. 查詢用戶的作品與合成歌曲 (api/feed/v2)
      for (int page = 0; page < maxPages; page++) {
        final url = Uri.parse('${SunoConstants.studioApiBase}/api/feed/v2?is_liked=false&limit=30&page=$page');
        final resp = await http.get(url, headers: headers).timeout(const Duration(seconds: 20));

        if (resp.statusCode != 200) break;

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final clips = (data['clips'] as List?) ?? [];
        if (clips.isEmpty) break;

        for (final c in clips) {
          if (c is! Map<String, dynamic>) continue;
          if (c['is_trashed'] == true) continue;

          // 核心：若為 4X 切片碎片，直接過濾剔除！
          if (isSliceClip(c)) continue;

          final id = (c['id'] as String? ?? '').trim();
          if (id.isEmpty) continue;

          final title = (c['title'] as String? ?? '').trim();
          final metadata = (c['metadata'] as Map<String, dynamic>?) ?? {};
          final promptLyrics = (metadata['prompt'] as String? ?? c['prompt'] as String? ?? '').trim();
          final audioUrl = c['audio_url'] as String?;
          final createdAtRaw = (c['created_at'] as String? ?? '').split('.')[0].replaceAll('T', ' ');
          final durationSec = (c['duration'] as num?)?.toDouble();
          final status = (c['status'] as String? ?? 'complete');

          // 如果已在本地清單，進行智慧更新（補充雲端音訊連結，保留本地拼音）
          if (existingClipMap.containsKey(id)) {
            final localItem = existingClipMap[id]!;
            if (audioUrl != null && audioUrl.isNotEmpty && localItem.audioUrl != audioUrl) {
              // 補充成曲音訊網址
              existingClipMap[id] = UploadHistoryItem(
                id: localItem.id,
                title: localItem.title.isNotEmpty ? localItem.title : (title.isNotEmpty ? title : '未命名歌曲'),
                lyrics: localItem.lyrics.isNotEmpty ? localItem.lyrics : promptLyrics,
                status: status,
                time: localItem.time.isNotEmpty ? localItem.time : createdAtRaw,
                clipId: localItem.clipId ?? id,
                renderId: localItem.renderId ?? id,
                songUrl: 'https://suno.com/song/$id',
                audioUrl: audioUrl,
                uploadMode: localItem.uploadMode,
                sourcePath: localItem.sourcePath,
                durationSec: durationSec ?? localItem.durationSec,
              );
              addedOrUpdatedCount++;
            }
          } else {
            // 本地未記錄（例如在 Mac 或其他裝置上傳的歌曲），自動導入成曲
            final newItem = UploadHistoryItem(
              id: 'suno_$id',
              title: title.isNotEmpty ? title : 'Suno 成品歌曲',
              lyrics: promptLyrics,
              status: status,
              time: createdAtRaw.isNotEmpty ? createdAtRaw : DateTime.now().toString().substring(0, 19),
              clipId: id,
              renderId: id,
              songUrl: 'https://suno.com/song/$id',
              audioUrl: audioUrl,
              uploadMode: 'sunoCloud',
              durationSec: durationSec,
            );
            newFetchedItems.add(newItem);
            existingClipMap[id] = newItem;
            addedOrUpdatedCount++;
          }
        }

        final hasMore = data['has_more'] as bool? ?? false;
        if (!hasMore) break;
      }

      // 合併與排序
      if (newFetchedItems.isNotEmpty) {
        _items.insertAll(0, newFetchedItems);
      }
      _items.sort((a, b) => b.time.compareTo(a.time));

      await _persist();
      notifyListeners();
    } catch (e) {
      debugPrint('[UploadHistoryService] 同步 Suno 雲端歷史失敗: $e');
    } finally {
      _isSyncingCloud = false;
      notifyListeners();
    }

    return addedOrUpdatedCount;
  }

  /// 新增一筆上傳記錄並存檔
  Future<void> addHistoryItem(UploadHistoryItem item) async {
    _items.insert(0, item);
    await _persist();
    notifyListeners();
  }

  /// 修改歌名與歌詞 (本地儲存 + 同步 Suno 雲端)
  Future<bool> updateItem({
    required String id,
    required String newTitle,
    required String newLyrics,
    String? token,
    String? deviceId,
  }) async {
    final index = _items.indexWhere((it) => it.id == id);
    if (index == -1) return false;

    final item = _items[index];
    item.title = newTitle;
    item.lyrics = newLyrics;

    await _persist();
    notifyListeners();

    // 如果提供了 Suno 憑證與 clipId / renderId，同步請求 Suno API 修改遠端資訊
    final clipId = item.renderId ?? item.clipId;
    if (token != null && token.isNotEmpty && clipId != null && clipId.isNotEmpty) {
      try {
        final url = Uri.parse('${SunoConstants.studioApiBase}/api/gen/$clipId/set_metadata/');
        final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);
        headers['Content-Type'] = 'application/json';

        final body = jsonEncode({
          'title': newTitle,
          'prompt': newLyrics,
          'lyrics': newLyrics,
          'is_audio_upload_tos_accepted': true,
        });

        final resp = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 20));
        debugPrint('[UploadHistoryService] 遠端同步 Suno 歌名/歌詞狀態: ${resp.statusCode}');
      } catch (e) {
        debugPrint('[UploadHistoryService] 遠端同步 Suno 失敗 (已保存在本地): $e');
      }
    }

    return true;
  }

  /// 刪除一筆記錄
  Future<void> deleteItem(String id) async {
    _items.removeWhere((it) => it.id == id);
    await _persist();
    notifyListeners();
  }

  /// 打開 Suno 歌曲連結
  void openSongUrl(UploadHistoryItem item) {
    final url = item.effectiveSongUrl;
    if (url.isNotEmpty) {
      try {
        final uri = Uri.parse(url);
        launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('[UploadHistoryService] 打開歌曲連結失敗: $e');
      }
    }
  }

  /// 保存至磁碟或本地儲存
  Future<void> _persist() async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final jsonList = _items.map((it) => it.toJson()).toList();
        await prefs.setString('xuanfeng_upload_history_json', jsonEncode(jsonList));
      } catch (e) {
        debugPrint('[UploadHistoryService] Web 持久化歷史失敗: $e');
      }
      return;
    }

    try {
      final path = await _getHistoryFilePath();
      final file = File(path);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final jsonList = _items.map((it) => it.toJson()).toList();
      final content = const JsonEncoder.withIndent('  ').convert(jsonList);
      await file.writeAsString(content);

      if (!kIsWeb && Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '';
        final oldPath = '$home/Library/Application Support/风聆Studio/upload_history.json';
        if (path != oldPath && await Directory('$home/Library/Application Support/风聆Studio').exists()) {
          try {
            await File(oldPath).writeAsString(content);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[UploadHistoryService] 持久化存檔失敗: $e');
    }
  }
}
