import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../models/audio_track.dart';
import '../models/upload_history_item.dart';

/// 全域音訊播放服務
/// 支援播放本地檔案 (DeviceFileSource)、記憶體 Bytes (BytesSource) 及 雲端 URL (UrlSource)
class AudioPlayerService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  String? _currentId;
  String? _currentTitle;
  String? _currentSource;
  bool _isLoading = false;

  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _completeSub;

  PlayerState get playerState => _playerState;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get currentId => _currentId;
  String? get currentTitle => _currentTitle;
  String? get currentSource => _currentSource;
  bool get isLoading => _isLoading;

  bool get isPlaying => _playerState == PlayerState.playing;
  bool get isPaused => _playerState == PlayerState.paused;
  bool get isActive => isPlaying || isPaused;

  AudioPlayerService() {
    _initListeners();
  }

  void _initListeners() {
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      _playerState = state;
      notifyListeners();
    });

    _posSub = _player.onPositionChanged.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
    });

    _completeSub = _player.onPlayerComplete.listen((_) {
      _playerState = PlayerState.completed;
      _position = Duration.zero;
      notifyListeners();
    });
  }

  /// 檢查特定 ID 是否正在播放
  bool isTrackPlaying(String? id) {
    if (id == null || _currentId == null) return false;
    return _currentId == id && isPlaying;
  }

  /// 檢查特定 ID 是否當前處於暫停
  bool isTrackPaused(String? id) {
    if (id == null || _currentId == null) return false;
    return _currentId == id && isPaused;
  }

  /// 播放或暫停（切換）
  Future<void> togglePlayHistoryItem(UploadHistoryItem item) async {
    if (_currentId == item.id) {
      if (isPlaying) {
        await pause();
      } else {
        await resume();
      }
      return;
    }
    await playHistoryItem(item);
  }

  /// 播放歷史記錄項目
  Future<void> playHistoryItem(UploadHistoryItem item) async {
    _isLoading = true;
    _currentId = item.id;
    _currentTitle = item.title;
    notifyListeners();

    try {
      await _player.stop();

      // 1. 優先檢查本地檔案 (sourcePath)
      if (item.sourcePath != null && item.sourcePath!.isNotEmpty) {
        if (!kIsWeb) {
          final file = File(item.sourcePath!);
          if (await file.exists()) {
            _currentSource = item.sourcePath;
            await _player.play(DeviceFileSource(item.sourcePath!));
            _isLoading = false;
            notifyListeners();
            return;
          }
        }
      }

      // 2. 其次嘗試 audioUrl (Suno 雲端音訊串流)
      if (item.audioUrl != null && item.audioUrl!.isNotEmpty) {
        _currentSource = item.audioUrl;
        await _player.play(UrlSource(item.audioUrl!));
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 3. 嘗試以 CDN 格式組合 Suno 音訊路徑 (若有 clipId 或 renderId)
      final clipId = item.renderId ?? item.clipId;
      if (clipId != null && clipId.isNotEmpty) {
        final cdnAudioUrl = 'https://cdn1.suno.ai/$clipId.mp3';
        _currentSource = cdnAudioUrl;
        await _player.play(UrlSource(cdnAudioUrl));
        _isLoading = false;
        notifyListeners();
        return;
      }

      throw Exception('找不到可播放的本機音檔或音訊串流連結');
    } catch (e) {
      debugPrint('[AudioPlayerService] 播放歷史音檔失敗: $e');
      _playerState = PlayerState.stopped;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 播放當前本地 AudioTrack
  Future<void> togglePlayTrack(AudioTrack track) async {
    final trackId = track.filePath.isNotEmpty ? track.filePath : track.fileName;
    if (_currentId == trackId) {
      if (isPlaying) {
        await pause();
      } else {
        await resume();
      }
      return;
    }
    await playTrack(track);
  }

  /// 播放本地 AudioTrack
  Future<void> playTrack(AudioTrack track) async {
    final trackId = track.filePath.isNotEmpty ? track.filePath : track.fileName;
    _isLoading = true;
    _currentId = trackId;
    _currentTitle = track.title.isNotEmpty ? track.title : track.fileNameWithoutExt;
    notifyListeners();

    try {
      await _player.stop();

      if (kIsWeb) {
        if (track.bytes != null && track.bytes!.isNotEmpty) {
          _currentSource = 'memory_bytes';
          await _player.play(BytesSource(track.bytes!));
        } else {
          throw Exception('Web 端缺少音訊記憶體資料');
        }
      } else {
        final file = File(track.filePath);
        if (await file.exists()) {
          _currentSource = track.filePath;
          await _player.play(DeviceFileSource(track.filePath));
        } else if (track.bytes != null && track.bytes!.isNotEmpty) {
          _currentSource = 'memory_bytes';
          await _player.play(BytesSource(track.bytes!));
        } else {
          throw Exception('本機檔案不存在: ${track.filePath}');
        }
      }
    } catch (e) {
      debugPrint('[AudioPlayerService] 播放本地音軌失敗: $e');
      _playerState = PlayerState.stopped;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 播放任意本機檔案或 URL
  Future<void> playCustom({
    required String id,
    required String title,
    String? filePath,
    String? url,
    Uint8List? bytes,
  }) async {
    _isLoading = true;
    _currentId = id;
    _currentTitle = title;
    notifyListeners();

    try {
      await _player.stop();
      if (filePath != null && !kIsWeb && await File(filePath).exists()) {
        _currentSource = filePath;
        await _player.play(DeviceFileSource(filePath));
      } else if (bytes != null && bytes.isNotEmpty) {
        _currentSource = 'bytes';
        await _player.play(BytesSource(bytes));
      } else if (url != null && url.isNotEmpty) {
        _currentSource = url;
        await _player.play(UrlSource(url));
      } else {
        throw Exception('未提供有效的音訊來源');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
    _playerState = PlayerState.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    await _player.resume();
    _playerState = PlayerState.playing;
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    _playerState = PlayerState.stopped;
    _position = Duration.zero;
    _currentId = null;
    _currentTitle = null;
    _currentSource = null;
    notifyListeners();
  }

  Future<void> seek(Duration pos) async {
    await _player.seek(pos);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
