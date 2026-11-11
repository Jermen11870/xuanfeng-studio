import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/audio_track.dart';
import 'audio_track_service.dart';

class YoutubeVideoInfo {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final int? viewCount;
  final DateTime? uploadDate;

  YoutubeVideoInfo({
    required this.id,
    required this.title,
    required this.author,
    this.duration,
    required this.thumbnailUrl,
    this.viewCount,
    this.uploadDate,
  });

  String get youtubeUrl => 'https://www.youtube.com/watch?v=$id';
  String get embedUrl => 'https://www.youtube.com/embed/$id?autoplay=1';

  String get formattedDuration {
    if (duration == null) return '--:--';
    final totalSec = duration!.inSeconds;
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedViews {
    if (viewCount == null) return '';
    if (viewCount! >= 100000000) {
      return '${(viewCount! / 100000000).toStringAsFixed(1)} 億次觀看';
    } else if (viewCount! >= 10000) {
      return '${(viewCount! / 10000).toStringAsFixed(1)} 萬次觀看';
    }
    return '$viewCount 次觀看';
  }
}

class YoutubeAudioService extends ChangeNotifier {
  final AudioTrackService audioTrackService;

  bool _isLoadingInfo = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';
  String? _errorMessage;
  YoutubeVideoInfo? _currentVideoInfo;
  String _lastFetchedUrl = '';
  String _sizeProgressText = '';

  YoutubeAudioService({required this.audioTrackService});

  bool get isLoadingInfo => _isLoadingInfo;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  int get percentage => (_downloadProgress * 100).toInt().clamp(0, 100);
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  YoutubeVideoInfo? get currentVideoInfo => _currentVideoInfo;
  String get formattedSizeProgress => _sizeProgressText;

  /// 探測本地可用的 ffmpeg 路徑
  String _findFfmpeg() {
    const homebrew = '/opt/homebrew/bin/ffmpeg';
    if (File(homebrew).existsSync()) return homebrew;

    const bundled = '/Applications/风聆Studio.app/Contents/Resources/bin/ffmpeg';
    if (File(bundled).existsSync()) return bundled;

    return 'ffmpeg';
  }

  /// 探測本地可用的 yt-dlp 路徑
  String? _findYtDlp() {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      '$home/Library/Application Support/旋風 studio/bin/yt-dlp',
      '/Users/jermen/Desktop/fengling_studio_flutter/assets/bin/yt-dlp',
      '/opt/homebrew/bin/yt-dlp',
      '/usr/local/bin/yt-dlp',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) {
        return c;
      }
    }
    return null;
  }

  /// 驗證是否為 YouTube 網址
  bool isValidYoutubeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final regExp = RegExp(
      r'^(https?:\/\/)?(www\.|m\.)?(youtube\.com\/(watch\?v=|shorts\/|live\/)|youtu\.be\/)[a-zA-Z0-9_-]{11}',
      caseSensitive: false,
    );
    return regExp.hasMatch(trimmed);
  }

  /// 提取影片資訊與縮圖
  Future<YoutubeVideoInfo?> fetchVideoInfo(String url) async {
    final trimmed = url.trim();
    if (!isValidYoutubeUrl(trimmed)) {
      _errorMessage = '請輸入正確的 YouTube 影片網址';
      notifyListeners();
      return null;
    }

    if (trimmed == _lastFetchedUrl && _currentVideoInfo != null) {
      return _currentVideoInfo;
    }

    _isLoadingInfo = true;
    _errorMessage = null;
    _statusMessage = '正在提取 YouTube 縮圖與影片資訊...';
    notifyListeners();

    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(trimmed);
      String thumb = video.thumbnails.highResUrl;
      if (thumb.isEmpty) thumb = video.thumbnails.mediumResUrl;
      if (thumb.isEmpty) thumb = video.thumbnails.lowResUrl;

      final info = YoutubeVideoInfo(
        id: video.id.value,
        title: video.title,
        author: video.author,
        duration: video.duration,
        thumbnailUrl: thumb,
        viewCount: video.engagement.viewCount,
        uploadDate: video.uploadDate,
      );
      _currentVideoInfo = info;
      _lastFetchedUrl = trimmed;
      _statusMessage = '已獲取資訊：${video.title}';
      return info;
    } catch (e) {
      debugPrint('[YoutubeAudioService] youtube_explode 獲取失敗，嘗試提取 VideoID: $e');
      // 若因 YouTube 反爬蟲限制失敗，從 URL 提取 videoId 作為兜底縮圖
      final videoId = _extractVideoId(trimmed);
      if (videoId != null && videoId.isNotEmpty) {
        final info = YoutubeVideoInfo(
          id: videoId,
          title: 'YouTube 影片 ($videoId)',
          author: 'YouTube',
          duration: null,
          thumbnailUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
        );
        _currentVideoInfo = info;
        _lastFetchedUrl = trimmed;
        _statusMessage = '已獲取影片縮圖與 ID';
        return info;
      }
      _errorMessage = '獲取資訊失敗：$e';
      return null;
    } finally {
      yt.close();
      _isLoadingInfo = false;
      notifyListeners();
    }
  }

  /// 從網址提取 11 位 Video ID
  String? _extractVideoId(String url) {
    final regExp = RegExp(r'(?:watch\?v=|shorts\/|live\/|youtu\.be\/)([a-zA-Z0-9_-]{11})');
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  /// 在 APP 內部打開 YouTube 視窗播放
  Future<void> playInApp(YoutubeVideoInfo info) async {
    try {
      if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        final webview = await WebviewWindow.create(
          configuration: CreateConfiguration(
            windowWidth: 880,
            windowHeight: 520,
            title: 'YouTube 播放 · ${info.title}',
            titleBarTopPadding: 10,
          ),
        );
        await webview.setApplicationNameForUserAgent(
          ' Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
        );
        webview.launch(info.embedUrl);
      } else {
        openInExternal(info);
      }
    } catch (e) {
      debugPrint('[YoutubeAudioService] 內嵌播放失敗，調用外部瀏覽器: $e');
      openInExternal(info);
    }
  }

  /// 調用系統預設 YouTube APP 或瀏覽器打開
  void openInExternal(YoutubeVideoInfo info) {
    try {
      final uri = Uri.parse(info.youtubeUrl);
      launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[YoutubeAudioService] 打開外部連結失敗: $e');
    }
  }

  /// 下載 YouTube 音訊並載入到 AudioTrackService（優先使用 yt-dlp 原生高速引擎，支援實時 % 滾動）
  Future<AudioTrack?> downloadAndLoadAudio(String url) async {
    final trimmed = url.trim();
    _isDownloading = true;
    _downloadProgress = 0.0;
    _sizeProgressText = '';
    _errorMessage = null;
    _statusMessage = '正在準備下載音訊... 0%';
    notifyListeners();

    if (kIsWeb) {
      _errorMessage = 'Web 瀏覽器受沙盒保護無法直接保存 YouTube 串流至本地磁碟。請直接選取/拖曳本地 MP3 檔案上傳，或在手機版 APK 進行 YouTube 一鍵下載！';
      _isDownloading = false;
      notifyListeners();
      return null;
    }

    try {
      Directory cacheDir;
      if (Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '';
        cacheDir = Directory('$home/Library/Application Support/旋風 studio/youtube_cache');
      } else {
        final tempDir = await getTemporaryDirectory();
        cacheDir = Directory('${tempDir.path}/xuanfeng_youtube_cache');
      }
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final ytdlp = _findYtDlp();
      final ffmpeg = _findFfmpeg();

      if (ytdlp != null) {
        debugPrint('[YoutubeAudioService] 使用 yt-dlp 引擎進行高速下載: $ytdlp');
        return await _downloadWithYtDlp(trimmed, ytdlp, ffmpeg, cacheDir);
      } else {
        debugPrint('[YoutubeAudioService] 使用 youtube_explode 備用引擎下載');
        return await _downloadWithExplode(trimmed, ffmpeg, cacheDir);
      }
    } catch (e) {
      _errorMessage = '下載失敗: $e';
      debugPrint('[YoutubeAudioService] 下載失敗: $e');
      return null;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// 核心引擎：使用 yt-dlp 下載並實時串流 % 進度
  Future<AudioTrack?> _downloadWithYtDlp(String url, String ytdlpPath, String ffmpegPath, Directory cacheDir) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outTemplate = '${cacheDir.path}/${timestamp}_%(title)s.%(ext)s';

    final args = [
      '-x',
      '--audio-format', 'mp3',
      '--audio-quality', '0',
      '--newline',
      '--no-playlist',
      '--ffmpeg-location', ffmpegPath,
      '-o', outTemplate,
      url,
    ];

    debugPrint('[YoutubeAudioService] 啟動進程: $ytdlpPath ${args.join(' ')}');
    final process = await Process.start(ytdlpPath, args);

    String? generatedFilePath;

    final downloadRegex = RegExp(r'\[download\]\s+([\d\.]+)%\s+of\s+([^\s]+)');
    final destinationRegex = RegExp(r'\[(?:download|ExtractAudio)\] Destination:\s+(.+)');

    // 監聽 stdout
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      debugPrint('[yt-dlp] $line');

      // 提取百分比進度
      final match = downloadRegex.firstMatch(line);
      if (match != null) {
        final pctStr = match.group(1);
        final sizeStr = match.group(2);
        if (pctStr != null) {
          final pct = double.tryParse(pctStr);
          if (pct != null) {
            _downloadProgress = (pct / 100.0).clamp(0.0, 1.0);
            _sizeProgressText = sizeStr ?? '';
            _statusMessage = '正在高速下載音訊... ${pct.toStringAsFixed(1)}%';
            notifyListeners();
          }
        }
      }

      // 提取產物檔案路徑
      final destMatch = destinationRegex.firstMatch(line);
      if (destMatch != null) {
        final path = destMatch.group(1)?.trim();
        if (path != null && (path.endsWith('.mp3') || path.endsWith('.m4a') || path.endsWith('.opus') || path.endsWith('.webm'))) {
          generatedFilePath = path;
        }
      }

      if (line.contains('[ExtractAudio]')) {
        _statusMessage = '正在將音訊轉換為 320kbps 頂級音質... 99%';
        notifyListeners();
      }
    });

    // 監聽 stderr
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      debugPrint('[yt-dlp err] $line');
    });

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw 'yt-dlp 下載失敗 (退出碼: $exitCode)';
    }

    // 尋找剛產生的音檔
    File? finalFile;
    if (generatedFilePath != null && File(generatedFilePath!).existsSync()) {
      finalFile = File(generatedFilePath!);
    } else {
      // 在 cache 目錄中依 timestamp 尋找
      final files = cacheDir.listSync().whereType<File>().toList();
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final f in files) {
        if (f.path.contains('$timestamp') && (f.path.endsWith('.mp3') || f.path.endsWith('.m4a'))) {
          finalFile = f;
          break;
        }
      }
    }

    if (finalFile == null || !finalFile.existsSync()) {
      throw '未找到下載完成的音訊檔案';
    }

    _downloadProgress = 1.0;
    _statusMessage = '音訊下載完成 (100%)，正在載入工作台...';
    notifyListeners();

    // 載入到 AudioTrackService
    final track = await audioTrackService.loadAudioFileFromPath(finalFile.path);
    if (track != null) {
      if (_currentVideoInfo != null && _currentVideoInfo!.title.isNotEmpty && !_currentVideoInfo!.title.startsWith('YouTube 影片 (')) {
        track.title = _currentVideoInfo!.title;
      } else {
        // 從檔名移除時間戳
        final baseName = finalFile.path.split('/').last.replaceAll(RegExp(r'^\d+_'), '').replaceAll('.mp3', '');
        track.title = baseName;
      }
      audioTrackService.notifyListeners();
    }

    _statusMessage = '音軌載入成功！';
    return track;
  }

  /// 備用引擎：使用 youtube_explode 下載 (增加超時防呆、多串流 Fallback 與平滑進度)
  Future<AudioTrack?> _downloadWithExplode(String url, String ffmpeg, Directory cacheDir) async {
    final yt = YoutubeExplode();
    try {
      _statusMessage = '正在解析 YouTube 影片資料... 5%';
      _downloadProgress = 0.05;
      notifyListeners();

      final video = await yt.videos.get(url).timeout(const Duration(seconds: 15));
      
      _statusMessage = '正在獲取高速音訊串流位址... 10%';
      _downloadProgress = 0.10;
      notifyListeners();

      final manifest = await yt.videos.streamsClient.getManifest(video.id).timeout(const Duration(seconds: 20));
      var audioStreams = manifest.audioOnly.sortByBitrate();
      
      StreamInfo? targetStream;
      if (audioStreams.isNotEmpty) {
        // 優先嘗試 mp4/m4a 音訊，相容性最廣且速度快
        final mp4Audio = audioStreams.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
        targetStream = mp4Audio.isNotEmpty ? mp4Audio.last : audioStreams.last;
      } else if (manifest.muxed.isNotEmpty) {
        targetStream = manifest.muxed.sortByBitrate().last;
      }

      if (targetStream == null) throw '未找到可用的音訊串流，請稍後重試';

      final totalBytes = targetStream.size.totalBytes;
      final ext = targetStream.container.name.toLowerCase();
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final rawPath = '${cacheDir.path}/${DateTime.now().millisecondsSinceEpoch}_$safeTitle.$ext';
      final rawFile = File(rawPath);

      _statusMessage = '已連接音訊串流，開始高速傳輸... 15%';
      _downloadProgress = 0.15;
      notifyListeners();

      final stream = yt.videos.streamsClient.get(targetStream);
      final output = rawFile.openWrite();
      int downloadedBytes = 0;

      await for (final data in stream) {
        downloadedBytes += data.length;
        output.add(data);
        if (totalBytes > 0) {
          final progress = 0.15 + (0.80 * (downloadedBytes / totalBytes)).clamp(0.0, 0.80);
          _downloadProgress = progress;
          _sizeProgressText = '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          _statusMessage = '正在高速下載音訊串流... $percentage%';
          notifyListeners();
        }
      }
      await output.flush();
      await output.close();

      _statusMessage = '音訊下載完成，正在載入工作台... 98%';
      _downloadProgress = 0.98;
      notifyListeners();

      final track = await audioTrackService.loadAudioFileFromPath(rawPath);
      if (track != null) {
        track.title = video.title;
        audioTrackService.notifyListeners();
      }
      _downloadProgress = 1.0;
      _statusMessage = '音軌載入成功！';
      notifyListeners();
      return track;
    } catch (e) {
      debugPrint('[YoutubeAudioService] _downloadWithExplode 異常: $e');
      throw '音訊串流下載失敗: $e';
    } finally {
      yt.close();
    }
  }

  void reset() {
    _currentVideoInfo = null;
    _errorMessage = null;
    _statusMessage = '';
    _downloadProgress = 0.0;
    _sizeProgressText = '';
    _isLoadingInfo = false;
    _isDownloading = false;
    notifyListeners();
  }
}
