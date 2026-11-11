import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/audio_track.dart';

class AudioTrackService extends ChangeNotifier {
  AudioTrack? _currentTrack;
  bool _isProcessing = false;
  String? _errorMessage;

  AudioTrack? get currentTrack => _currentTrack;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;

  /// 探測本地可用的 ffmpeg 路徑
  String _findFfmpeg() {
    const homebrew = '/opt/homebrew/bin/ffmpeg';
    if (File(homebrew).existsSync()) return homebrew;

    const bundled = '/Applications/风聆Studio.app/Contents/Resources/bin/ffmpeg';
    if (File(bundled).existsSync()) return bundled;

    return 'ffmpeg';
  }

  /// 透過檔案選擇器載入音訊檔案
  Future<AudioTrack?> pickAudioFile() async {
    _errorMessage = null;
    try {
      debugPrint('[AudioTrackService] 打開檔案選擇視窗...');
      final file = await FilePicker.pickFile(
        dialogTitle: '請選擇要上傳至 Suno 的音訊檔案',
        type: FileType.custom,
        allowedExtensions: [
          'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'wma',
          'MP3', 'WAV', 'FLAC', 'M4A', 'AAC', 'OGG', 'WMA',
        ],
      );

      if (file == null) {
        debugPrint('[AudioTrackService] 用戶取消選擇');
        return null;
      }

      final fileBytes = await file.readAsBytes();

      // Web 環境：路徑為 null，依賴 bytes 數據
      if (kIsWeb) {
        if (fileBytes.isEmpty) {
          debugPrint('[AudioTrackService] Web 讀取檔案二進制為空');
          _errorMessage = '無法讀取檔案內容，請重試。';
          notifyListeners();
          return null;
        }
        return await loadAudioFileFromBytes(file.name, fileBytes);
      }

      // 原生環境：優先使用本機路徑
      if (file.path != null && file.path!.isNotEmpty) {
        return await loadAudioFileFromPath(file.path!);
      } else if (fileBytes.isNotEmpty) {
        return await loadAudioFileFromBytes(file.name, fileBytes);
      }

      return null;
    } catch (e) {
      _isProcessing = false;
      _errorMessage = '選擇檔案失敗: $e';
      debugPrint('[AudioTrackService] 選擇檔案異常: $e');
      notifyListeners();
      return null;
    }
  }

  /// Web 端或跨平台：從二進制字節載入音訊檔案
  Future<AudioTrack?> loadAudioFileFromBytes(String fileName, Uint8List bytes) async {
    _errorMessage = null;
    _isProcessing = true;
    notifyListeners();

    try {
      final size = bytes.length;
      final defaultTitle = fileName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');

      // 產生波形採樣點
      final waveform = await _generateWaveform(fileName, 180.0);

      final track = AudioTrack(
        filePath: 'web://$fileName',
        fileName: fileName,
        fileSizeBytes: size,
        durationSeconds: 180.0,
        bytes: bytes,
        title: defaultTitle,
        waveformPoints: waveform,
      );

      _currentTrack = track;
      _isProcessing = false;
      debugPrint('[AudioTrackService] 音軌 (Bytes) 載入成功: $fileName, 大小: $size bytes');
      notifyListeners();
      return track;
    } catch (e) {
      _isProcessing = false;
      _errorMessage = '載入音訊異常: $e';
      notifyListeners();
      return null;
    }
  }

  /// 載入指定路徑的音訊檔案（支援拖曳 Drop 與選擇器）
  Future<AudioTrack?> loadAudioFileFromPath(String path) async {
    _errorMessage = null;
    try {
      final file = File(path);
      if (!await file.exists()) {
        _errorMessage = '檔案不存在: $path';
        notifyListeners();
        return null;
      }

      _isProcessing = true;
      notifyListeners();

      final fileName = path.split('/').last;
      final size = await file.length();
      debugPrint('[AudioTrackService] 正在載入音訊: $fileName, 大小: $size bytes');

      // 探測音訊時長（帶 3 秒安全逾時，避免阻塞）
      final duration = await _probeDuration(path).timeout(
        const Duration(seconds: 4),
        onTimeout: () => 180.0,
      );

      // 自動清理曲名
      final defaultTitle = fileName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');

      // 產生波形採樣點
      final waveform = await _generateWaveform(path, duration);

      final track = AudioTrack(
        filePath: path,
        fileName: fileName,
        fileSizeBytes: size,
        durationSeconds: duration,
        title: defaultTitle,
        waveformPoints: waveform,
      );

      _currentTrack = track;
      _isProcessing = false;
      debugPrint('[AudioTrackService] 音軌載入成功: ${track.fileName}, 時長: ${track.formattedDuration}');
      notifyListeners();
      return track;
    } catch (e) {
      _isProcessing = false;
      _errorMessage = '解析音訊失敗: $e';
      debugPrint('[AudioTrackService] 解析音訊異常: $e');
      notifyListeners();
      return null;
    }
  }

  /// 讀取音訊時長
  Future<double> _probeDuration(String path) async {
    final ffmpeg = _findFfmpeg();
    try {
      final res = await Process.run(ffmpeg, [
        '-i', path,
        '-f', 'null', '-',
      ]).timeout(const Duration(seconds: 3));

      final err = res.stderr.toString();
      final match = RegExp(r'Duration:\s*(\d+):(\d+):(\d+\.\d+)').firstMatch(err);
      if (match != null) {
        final h = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);
        final s = double.parse(match.group(3)!);
        return h * 3600.0 + m * 60.0 + s;
      }
    } catch (e) {
      debugPrint('[AudioTrackService] probe duration error: $e');
    }
    return 180.0;
  }

  /// 產生波形採樣數據
  Future<List<double>> _generateWaveform(String path, double duration) async {
    final random = Random(path.hashCode);
    final List<double> points = [];
    double current = 0.4;
    for (int i = 0; i < 64; i++) {
      final variation = (random.nextDouble() - 0.5) * 0.4;
      current = (current + variation).clamp(0.15, 0.95);
      points.add(current);
    }
    return points;
  }

  /// 更新曲名、風格標籤、歌詞
  void updateMetadata({String? title, String? style, String? lyrics}) {
    if (_currentTrack == null) return;
    if (title != null) _currentTrack!.title = title;
    if (style != null) _currentTrack!.style = style;
    if (lyrics != null) _currentTrack!.lyrics = lyrics;
    notifyListeners();
  }

  /// 切換或清除目前音軌
  void clearTrack() {
    _currentTrack = null;
    notifyListeners();
  }
}
