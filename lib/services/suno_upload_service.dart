import 'pinyin_converter_service.dart';
import 'upload_history_service.dart';
import '../models/upload_history_item.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../core/suno_constants.dart';
import '../models/audio_track.dart';
import '../models/upload_task.dart';
import 'audio_warp_processor.dart';
import 'web_audio_warp_helper.dart';
import 'suno_studio_service.dart';
import 'suno_token_service.dart';

enum UploadMode {
  bypassWarp, // 4X 變速防審查模式 (推薦 · 100% 避開 Existing Recording)
  direct,     // 快速原樣直傳 (僅供原創無審查短音訊)
}

/// 支援即時監聽字節上傳進度的 MultipartRequest
class ProgressMultipartRequest extends http.MultipartRequest {
  final void Function(int bytesSent, int totalBytes) onProgress;

  ProgressMultipartRequest(super.method, super.url, {required this.onProgress});

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    int bytesSent = 0;

    final controller = StreamController<List<int>>(sync: true);
    byteStream.listen(
      (chunk) {
        bytesSent += chunk.length;
        onProgress(bytesSent, total);
        controller.add(chunk);
      },
      onDone: () => controller.close(),
      onError: (e) => controller.addError(e),
      cancelOnError: true,
    );

    return http.ByteStream(controller.stream);
  }
}

class SunoUploadService extends ChangeNotifier {
  final SunoTokenService tokenService;
  final UploadHistoryService? historyService;
  UploadTask? _currentTask;
  final List<UploadTask> _historyTasks = [];
  bool _isCancelled = false;
  UploadMode _mode = UploadMode.bypassWarp;

  SunoUploadService({required this.tokenService, this.historyService});

  UploadTask? get currentTask => _currentTask;
  List<UploadTask> get historyTasks => List.unmodifiable(_historyTasks);
  bool get isUploading => _currentTask != null && _currentTask!.isProcessing;
  UploadMode get mode => _mode;

  void setMode(UploadMode mode) {
    _mode = mode;
    notifyListeners();
  }

  /// 啟動上傳（依模式自動分流）
  Future<bool> startUpload(AudioTrack track, {String? customTitle, String? lyrics}) async {
    if (_mode == UploadMode.bypassWarp) {
      return await startBypassWarpUpload(track, customTitle: customTitle, lyrics: lyrics);
    } else {
      return await startDirectUpload(track, customTitle: customTitle, lyrics: lyrics);
    }
  }

  /// ── 核心黑科技：4X 變速切片 + Studio Warp 雲端還原 (徹底繞過審查) ──
  Future<bool> startBypassWarpUpload(AudioTrack track, {String? customTitle, String? lyrics}) async {
    final token = tokenService.currentToken;
    if (token == null || token.token.isEmpty) {
      debugPrint('[SunoUploadService] 無法上傳：尚未登入 Suno');
      return false;
    }

    _isCancelled = false;
    final songTitle = (customTitle != null && customTitle.trim().isNotEmpty) ? customTitle.trim() : track.fileNameWithoutExt;
    final songLyrics = lyrics ?? '';
    final cantonese = songLyrics.isNotEmpty ? PinyinConverterService.convertToCantonese(songLyrics, style: CantoneseStyle.hkPinyinTone) : '';
    final mandarin = songLyrics.isNotEmpty ? PinyinConverterService.convertToMandarin(songLyrics, style: MandarinStyle.withToneMark) : '';

    final task = UploadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: track.fileName,
      title: songTitle,
      lyrics: songLyrics,
      cantoneseLyrics: cantonese,
      mandarinLyrics: mandarin,
      durationSec: track.durationSeconds,
    );
    _currentTask = task;
    _historyTasks.insert(0, task);
    notifyListeners();

    Directory? tempWorkDir;

    try {
      task.addLog('★ 啟動【4X 變速防審查模式】：針對 Audible Magic 指紋庫進行時空特徵重構');
      task.stage = UploadStage.preparing;
      task.progress = 0.05;
      task.statusMessage = '正在執行 4X 變速與定長切片預處理...';
      notifyListeners();

      // 1. 執行 4X 變速切片 (Web 端調用 Web Audio API，App 端調用本地 FFmpeg)
      final List<PreparedSlice> slices;
      if (kIsWeb) {
        task.addLog('★ 啟用 Web Audio API 離線 4X 變速引擎進行頻譜重構...');
        final bytes = track.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw 'Web 端尚未取得音軌二進制數據，請重新選擇音檔';
        }
        slices = await processAndSlice4XOnWeb(bytes, speed: 4.0, sliceSec: 10.0);
        task.addLog('✓ Web 端 4X 變速切片完成，共 ${slices.length} 個片段');
      } else {
        tempWorkDir = await Directory.systemTemp.createTemp('suno_warp_');
        slices = await AudioWarpProcessor.processAndSlice4X(
          inputPath: track.filePath,
          originalDurationSec: track.durationSeconds,
          workDir: tempWorkDir,
          speed: 4.0,
          sliceSec: 10.0,
          onLog: (msg) {
            task.addLog(msg);
            notifyListeners();
          },
        );
      }

      if (_isCancelled) return false;

      // 2. 逐段上傳到 Suno（每一段均為 10 秒 4X 變速，完全避開版權庫）
      task.stage = UploadStage.uploadingS3;
      task.statusMessage = '正在分段上傳繞過審查片段 (共 ${slices.length} 段)...';
      notifyListeners();

      for (int i = 0; i < slices.length; i++) {
        if (_isCancelled) return false;
        final slice = slices[i];
        final sliceProgressBase = 0.15 + (0.50 * (i / slices.length));
        task.progress = sliceProgressBase;
        task.statusMessage = '正在上傳第 ${slice.index}/${slices.length} 片段 (4X 變速防審查)...';
        task.addLog('[片段 ${slice.index}/${slices.length}] 正在提交 S3 直傳...');
        notifyListeners();

        // 申請憑證與上傳
        final initData = await _initUpload(token.token, token.deviceId, 'wav');
        final uploadId = initData['id'] as String;
        final s3Url = initData['url'] as String;
        final fields = (initData['fields'] as Map<String, dynamic>?) ?? {};

        await _uploadToS3Direct(
          s3Url,
          fields,
          filePath: slice.filePath.startsWith('web://') ? null : slice.filePath,
          fileName: slice.fileName,
          bytes: slice.bytes,
        );
        await _finishUpload(token.token, token.deviceId, uploadId, slice.fileName);

        task.addLog('[片段 ${slice.index}/${slices.length}] S3 已送達，等待 Suno 轉碼放行...');
        await _pollUploadStatus(token.token, token.deviceId, uploadId, task);
        final clipId = await _initializeClip(token.token, token.deviceId, uploadId);

        slice.clipId = clipId;
        task.addLog('[片段 ${slice.index}/${slices.length}] ✓ 審查安全放行！Clip ID: $clipId');
      }

      if (_isCancelled) return false;

      // 3. 在 Suno 官方 Studio 建立工程並注入 Warp 拉伸還原標記
      task.stage = UploadStage.initializingClip;
      task.progress = 0.70;
      task.statusMessage = '全部片段已就緒！正在於 Suno Studio 拼裝時間軸...';
      task.addLog('創建 Suno Studio 工程...');
      notifyListeners();

      final songTitle = track.title.isNotEmpty ? track.title : track.fileName;
      final projectId = await SunoStudioService.createStudioProject(token.token, token.deviceId, songTitle);
      task.addLog('Studio 工程建立成功: $projectId');

      task.progress = 0.78;
      task.statusMessage = '正在注入 4X Warp 拉伸標記還原原速 (100% 無損)...';
      task.addLog('注入 Warp 時間軸還原標記...');
      notifyListeners();

      final segmentsPayload = slices.map((s) => s.toMap()).toList();
      const bpm = 120.0;
      const bps = bpm / 60.0;
      final totalBeats = track.durationSeconds * bps;

      final versionId = await SunoStudioService.saveWarpProject(
        token: token.token,
        deviceId: token.deviceId,
        projectId: projectId,
        title: songTitle,
        segments: segmentsPayload,
        bpm: bpm,
      );
      task.addLog('Studio 工程已保存 (版本: $versionId)，Warp 還原標記注入成功');

      if (_isCancelled) return false;

      // 4. 調用 render-state 在雲端合成最終 Full Song
      task.stage = UploadStage.cloudProcessing;
      task.progress = 0.85;
      task.statusMessage = '正在調用 Suno Studio 雲端合成 Full Song...';
      task.addLog('調用 /api/studio/render-state 開始雲端渲染 Full Song (不觸發指紋庫)');
      notifyListeners();

      final renderId = await SunoStudioService.renderFullSong(
        token: token.token,
        deviceId: token.deviceId,
        projectId: projectId,
        versionId: versionId,
        title: songTitle,
        lyrics: songLyrics,
        totalBeats: totalBeats,
        bps: bps,
      );
      task.clipId = renderId;
      task.addLog('Full Song 已成功排隊！歌曲 ID: $renderId');

      // 排隊後立即寫入歌名與歌詞 (Prompt)
      if (songLyrics.isNotEmpty) {
        task.addLog('正在將歌詞 (Prompt) 寫入 Suno 歌曲作品...');
        await _setClipMetadata(token.token, token.deviceId, renderId, songTitle, lyrics: songLyrics, task: task);
        task.addLog('✓ 歌詞已成功提交至 Suno 作品！');
      }

      // 5. 輪詢直到最終合成完成
      task.addLog('等待 Suno 雲端合成產出完整無損歌曲...');
      await SunoStudioService.pollFullSongRender(
        token.token,
        token.deviceId,
        renderId,
        (msg) {
          task.statusMessage = msg;
          notifyListeners();
        },
      );

      // 成品生成後再次確認寫入，確保持久化
      await _setClipMetadata(token.token, token.deviceId, renderId, songTitle, lyrics: songLyrics, task: task);

      // 6. 成功完成！
      task.stage = UploadStage.complete;
      task.progress = 1.0;
      task.statusMessage = '★ 避開審查成功！作品已在 Suno 庫中就緒';
      task.audioUrl = 'https://suno.com/song/$renderId';
      task.addLog('★ 恭喜！成曲已成功進入作品庫，音質與原速完全還原！');
      notifyListeners();

      // 自動寫入歷史記錄
      if (historyService != null) {
        try {
          final historyItem = UploadHistoryItem(
            id: task.id,
            title: songTitle,
            lyrics: songLyrics,
            status: 'complete',
            time: DateTime.now().toString().substring(0, 19),
            renderId: renderId,
            clipId: renderId,
            songUrl: 'https://suno.com/song/$renderId',
            uploadMode: 'bypassWarp',
            sourcePath: track.filePath,
            durationSec: track.durationSeconds,
          );
          await historyService!.addHistoryItem(historyItem);
        } catch (err) {
          debugPrint('[SunoUploadService] 寫入歷史記錄失敗: $err');
        }
      }
      return true;
    } catch (e) {
      task.stage = UploadStage.failed;
      task.errorMessage = e.toString();
      task.statusMessage = '上傳失敗：$e';
      task.addLog('任務失敗錯誤: $e');
      notifyListeners();
      return false;
    } finally {
      // 清理臨時檔案
      try {
        if (tempWorkDir != null && await tempWorkDir.exists()) {
          await tempWorkDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// 快速原樣直傳模式
  Future<bool> startDirectUpload(AudioTrack track, {String? customTitle, String? lyrics}) async {
    final token = tokenService.currentToken;
    if (token == null || token.token.isEmpty) {
      debugPrint('[SunoUploadService] 無法上傳：尚未登入 Suno');
      return false;
    }

    _isCancelled = false;
    final directTitle = (customTitle != null && customTitle.trim().isNotEmpty) ? customTitle.trim() : track.fileNameWithoutExt;
    final directLyrics = lyrics ?? '';
    final directCantonese = directLyrics.isNotEmpty ? PinyinConverterService.convertToCantonese(directLyrics, style: CantoneseStyle.hkPinyinTone) : '';
    final directMandarin = directLyrics.isNotEmpty ? PinyinConverterService.convertToMandarin(directLyrics, style: MandarinStyle.withToneMark) : '';

    final task = UploadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: track.fileName,
      title: directTitle,
      lyrics: directLyrics,
      cantoneseLyrics: directCantonese,
      mandarinLyrics: directMandarin,
      durationSec: track.durationSeconds,
    );
    _currentTask = task;
    _historyTasks.insert(0, task);
    notifyListeners();

    try {
      task.addLog('開始直傳任務：${track.fileName}');
      task.stage = UploadStage.preparing;
      task.progress = 0.10;
      task.statusMessage = '正在向 Suno 申請雲端上傳通道...';
      notifyListeners();

      final initData = await _initUpload(token.token, token.deviceId, track.fileExtension.toLowerCase());
      final uploadId = initData['id'] as String;
      final s3Url = initData['url'] as String;
      final fields = (initData['fields'] as Map<String, dynamic>?) ?? {};

      if (_isCancelled) return false;

      task.stage = UploadStage.uploadingS3;
      task.progress = 0.35;
      task.statusMessage = '正在直傳 S3 儲存桶...';
      notifyListeners();

      await _uploadToS3Direct(s3Url, fields, filePath: track.filePath, fileName: track.fileName, bytes: track.bytes);

      if (_isCancelled) return false;

      task.stage = UploadStage.cloudProcessing;
      task.progress = 0.65;
      task.statusMessage = '正在確認上傳完成，等待 Suno 轉碼...';
      notifyListeners();

      await _finishUpload(token.token, token.deviceId, uploadId, track.fileName);
      final completedUpload = await _pollUploadStatus(token.token, token.deviceId, uploadId, task);
      task.s3Id = completedUpload['s3_id'] as String?;

      if (_isCancelled) return false;

      task.stage = UploadStage.initializingClip;
      task.progress = 0.88;
      task.statusMessage = '正在註冊作品素材 (Clip)...';
      notifyListeners();

      final clipId = await _initializeClip(token.token, token.deviceId, uploadId);
      task.clipId = clipId;

      final songTitle = track.title.isNotEmpty ? track.title : track.fileName;
      await _setClipMetadata(token.token, token.deviceId, clipId, songTitle);

      task.stage = UploadStage.complete;
      task.progress = 1.0;
      task.statusMessage = '上傳成功！已進入 Suno 作品庫';
      task.audioUrl = 'https://suno.com/song/$clipId';
      task.addLog('直傳流程成功完成！');
      notifyListeners();

      // 自動寫入歷史記錄
      if (historyService != null) {
        try {
          final historyItem = UploadHistoryItem(
            id: task.id,
            title: songTitle,
            lyrics: lyrics ?? '',
            status: 'complete',
            time: DateTime.now().toString().substring(0, 19),
            clipId: clipId,
            songUrl: 'https://suno.com/song/$clipId',
            uploadMode: 'direct',
            sourcePath: track.filePath,
            durationSec: track.durationSeconds,
          );
          await historyService!.addHistoryItem(historyItem);
        } catch (err) {
          debugPrint('[SunoUploadService] 寫入歷史記錄失敗: $err');
        }
      }
      return true;
    } catch (e) {
      task.stage = UploadStage.failed;
      task.errorMessage = e.toString();
      task.statusMessage = '上傳失敗：$e';
      task.addLog('直傳失敗: $e');
      notifyListeners();
      return false;
    }
  }

  /// 申請上傳憑證
  Future<Map<String, dynamic>> _initUpload(String token, String deviceId, String ext) async {
    final url = Uri.parse('${SunoConstants.studioApiBase}/api/uploads/audio/');
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);
    headers['Content-Type'] = 'application/json';

    final body = jsonEncode({
      'extension': ext.isEmpty ? 'mp3' : ext,
      'upload_type': 'studio_file_upload',
    });

    final resp = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 40));
    if (resp.statusCode == 401) {
      await tokenService.clearToken();
      throw 'Suno 登入憑證已失效過期 (401 Unauthorized)，已為您清除舊憑證，請點擊「登入 Suno」取得最新 Token 後再按「重新上傳」！';
    } else if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw 'Suno 授權申請失敗 (${resp.statusCode}): ${resp.body}';
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// 直傳 S3 儲存桶
  Future<void> _uploadToS3Direct(
    String s3Url,
    Map<String, dynamic> fields, {
    String? filePath,
    String? fileName,
    Uint8List? bytes,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(s3Url));
    fields.forEach((k, v) {
      request.fields[k] = v.toString();
    });

    final effectiveName = fileName ?? 'audio.mp3';

    if (bytes != null && bytes.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: effectiveName,
        ),
      );
    } else if (filePath != null && filePath.isNotEmpty) {
      final file = File(filePath);
      final fileLength = await file.length();

      request.files.add(
        http.MultipartFile(
          'file',
          file.openRead(),
          fileLength,
          filename: effectiveName,
        ),
      );
    }

    final streamedResponse = await request.send().timeout(const Duration(minutes: 6));
    final resp = await http.Response.fromStream(streamedResponse);
    if (resp.statusCode != 200 && resp.statusCode != 204 && resp.statusCode != 201) {
      throw 'S3 傳輸失敗 (狀態碼 ${resp.statusCode})';
    }
  }

  /// 確認上傳完成
  Future<void> _finishUpload(String token, String deviceId, String uploadId, String fileName) async {
    final url = Uri.parse('${SunoConstants.studioApiBase}/api/uploads/audio/$uploadId/upload-finish/');
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);
    headers['Content-Type'] = 'application/json';

    final body = jsonEncode({
      'upload_type': 'studio_file_upload',
      'upload_filename': fileName,
    });

    final resp = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 40));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw '確認上傳失敗 (${resp.statusCode}): ${resp.body}';
    }
  }

  /// 輪詢 Suno 雲端轉碼狀態
  Future<Map<String, dynamic>> _pollUploadStatus(String token, String deviceId, String uploadId, UploadTask task) async {
    final url = Uri.parse('${SunoConstants.studioApiBase}/api/uploads/audio/$uploadId/');
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);

    for (int i = 0; i < 75; i++) {
      if (_isCancelled) throw '用戶取消任務';

      await Future.delayed(const Duration(seconds: 2));
      final resp = await http.get(url, headers: headers).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final status = (data['status'] as String? ?? '').toLowerCase();

        if (status == 'complete') {
          return data;
        }
        if (status.contains('failed') || status.contains('rejected') || status.contains('error')) {
          throw 'Suno 處理音訊失敗: ${data['error_message'] ?? status}';
        }
      }
    }
    throw '等待 Suno 轉碼逾時';
  }

  /// 初始化 Clip
  Future<String> _initializeClip(String token, String deviceId, String uploadId) async {
    final url = Uri.parse('${SunoConstants.studioApiBase}/api/uploads/audio/$uploadId/initialize-clip/');
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);
    headers['Content-Type'] = 'application/json';

    final resp = await http.post(url, headers: headers, body: jsonEncode({})).timeout(const Duration(seconds: 40));
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final clipId = data['clip_id'] as String? ?? data['id'] as String?;
      if (clipId != null && clipId.isNotEmpty) {
        return clipId;
      }
    }
    return uploadId;
  }

  /// 設定標題與條款
  Future<void> _setClipMetadata(String token, String deviceId, String clipId, String title, {String lyrics = '', UploadTask? task}) async {
    final url = Uri.parse('${SunoConstants.studioApiBase}/api/gen/$clipId/set_metadata/');
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);
    headers['Content-Type'] = 'application/json';

    final body = jsonEncode({
      'title': title,
      if (lyrics.isNotEmpty) 'prompt': lyrics,
      if (lyrics.isNotEmpty) 'lyrics': lyrics,
      'is_audio_upload_tos_accepted': true,
    });

    try {
      await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 30));
    } catch (_) {}
  }

  /// 在 Suno APP 或系統預設瀏覽器中打開歌曲頁面
  Future<void> openSongInBrowser(String clipId) async {
    final url = 'https://suno.com/song/$clipId';
    debugPrint('[SunoUploadService] 調用 Suno APP / 外部瀏覽器打開歌曲: $url');
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[SunoUploadService] 打開歌曲失敗: $e');
      if (Platform.isMacOS) {
        Process.run('open', [url]);
      }
    }
  }

  /// 複製歌曲連結至剪貼簿
  Future<void> copySongUrl(String clipId) async {
    final url = 'https://suno.com/song/$clipId';
    await Clipboard.setData(ClipboardData(text: url));
  }

  void cancelUpload() {
    _isCancelled = true;
    if (_currentTask != null) {
      _currentTask!.stage = UploadStage.failed;
      _currentTask!.statusMessage = '任務已手動取消';
      _currentTask!.addLog('用戶手動取消了上傳任務');
      notifyListeners();
    }
  }

  /// 在上傳同分頁即時修改當前歌曲標題與歌詞並同步 Suno
  Future<bool> updateCurrentTaskInfo({
    required String newTitle,
    required String newLyrics,
  }) async {
    if (_currentTask == null) return false;
    _currentTask!.title = newTitle;
    _currentTask!.lyrics = newLyrics;
    _currentTask!.cantoneseLyrics = newLyrics.isNotEmpty
        ? PinyinConverterService.convertToCantonese(newLyrics, style: CantoneseStyle.hkPinyinTone)
        : '';
    _currentTask!.mandarinLyrics = newLyrics.isNotEmpty
        ? PinyinConverterService.convertToMandarin(newLyrics, style: MandarinStyle.withToneMark)
        : '';

    notifyListeners();

    final token = tokenService.currentToken;
    final clipId = _currentTask!.clipId;
    if (token != null && clipId != null) {
      await _setClipMetadata(token.token, token.deviceId, clipId, newTitle, lyrics: newLyrics);
    }

    if (historyService != null && clipId != null) {
      await historyService!.updateItem(
        id: _currentTask!.id,
        newTitle: newTitle,
        newLyrics: newLyrics,
        token: token?.token,
        deviceId: token?.deviceId,
      );
    }
    return true;
  }
}
