import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class PreparedSlice {
  final int index;
  final String filePath;
  final String fileName;
  final double timelineStartSec;
  final double timelineEndSec;
  final double spedDurationSec;
  final double speed;
  final Uint8List? bytes;
  String? clipId;

  PreparedSlice({
    required this.index,
    required this.filePath,
    required this.fileName,
    required this.timelineStartSec,
    required this.timelineEndSec,
    required this.spedDurationSec,
    required this.speed,
    this.bytes,
    this.clipId,
  });

  Map<String, dynamic> toMap() {
    return {
      'index': index,
      'filePath': filePath,
      'fileName': fileName,
      'timelineStartSec': timelineStartSec,
      'timelineEndSec': timelineEndSec,
      'spedDurationSec': spedDurationSec,
      'speed': speed,
      'clipId': clipId,
    };
  }
}

class AudioWarpProcessor {
  static String findFfmpeg() {
    const homebrew = '/opt/homebrew/bin/ffmpeg';
    if (File(homebrew).existsSync()) return homebrew;

    const bundled = '/Applications/风聆Studio.app/Contents/Resources/bin/ffmpeg';
    if (File(bundled).existsSync()) return bundled;

    return 'ffmpeg';
  }

  /// 跨平台執行 FFmpeg 指令 (Android/iOS 調用原生 C/C++ 庫，桌面端調用本機進程)
  static Future<void> _runFfmpeg(List<String> args, {required String errorPrefix}) async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw '$errorPrefix: $logs';
      }
    } else {
      final ffmpeg = findFfmpeg();
      final res = await Process.run(ffmpeg, args);
      if (res.exitCode != 0) {
        throw '$errorPrefix: ${res.stderr}';
      }
    }
  }

  /// 執行 4X 變速壓縮並按照 10 秒定長切片
  static Future<List<PreparedSlice>> processAndSlice4X({
    required String inputPath,
    required double originalDurationSec,
    required Directory workDir,
    double speed = 4.0,
    double sliceSec = 10.0,
    void Function(String msg)? onLog,
  }) async {
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }

    onLog?.call('啟動 4X 變速處理：破壞聲學指紋包絡線，避開 Audible Magic 審查');

    // 1. 產生 4X 變速音訊
    final spedAudioPath = '${workDir.path}/preproc_spd${speed.toInt()}x.wav';
    final filter = speed == 4.0 ? 'atempo=2.0,atempo=2.0' : 'atempo=$speed';

    await _runFfmpeg([
      '-y',
      '-hide_banner',
      '-loglevel', 'error',
      '-i', inputPath,
      '-filter:a', filter,
      '-ar', '44100',
      '-ac', '2',
      '-acodec', 'pcm_s16le',
      spedAudioPath,
    ], errorPrefix: '4X 變速處理失敗');

    if (!await File(spedAudioPath).exists()) {
      throw '4X 變速處理失敗：找不到生成之檔案 $spedAudioPath';
    }

    final totalSpedSec = originalDurationSec / speed;
    onLog?.call('4X 壓縮完成：原長 ${originalDurationSec.toStringAsFixed(1)}秒 ➔ 變速後 ${totalSpedSec.toStringAsFixed(1)}秒');

    // 2. 規劃切片區間 (10 秒一段，尾段不足 5 秒併入上一段)
    final bounds = <List<double>>[];
    double pos = 0.0;
    while (pos + sliceSec <= totalSpedSec) {
      bounds.add([pos, pos + sliceSec]);
      pos += sliceSec;
    }

    final remainder = totalSpedSec - pos;
    if (remainder >= 5.0 || bounds.isEmpty) {
      if (remainder > 0.05) {
        bounds.add([pos, totalSpedSec]);
      }
    } else if (remainder > 0.05 && bounds.isNotEmpty) {
      final last = bounds.removeLast();
      bounds.add([last[0], totalSpedSec]);
    }

    onLog?.call('開始切割 10 秒定長短片，共 ${bounds.length} 個片段');

    // 3. 執行實體切片
    final List<PreparedSlice> slices = [];
    for (int i = 0; i < bounds.length; i++) {
      final start = bounds[i][0];
      final end = bounds[i][1];
      final dur = end - start;
      final sliceIdx = i + 1;
      final sliceFileName = 'slice_${sliceIdx.toString().padLeft(2, '0')}.wav';
      final sliceFilePath = '${workDir.path}/$sliceFileName';

      await _runFfmpeg([
        '-y',
        '-hide_banner',
        '-loglevel', 'error',
        '-ss', start.toStringAsFixed(3),
        '-t', dur.toStringAsFixed(3),
        '-i', spedAudioPath,
        '-ar', '44100',
        '-ac', '2',
        '-acodec', 'pcm_s16le',
        sliceFilePath,
      ], errorPrefix: '切割片段 $sliceIdx 失敗');

      if (!await File(sliceFilePath).exists()) {
        throw '切割片段 $sliceIdx 失敗：找不到生成之檔案 $sliceFilePath';
      }

      final timelineStart = start * speed;
      final timelineEnd = end * speed;

      slices.add(
        PreparedSlice(
          index: sliceIdx,
          filePath: sliceFilePath,
          fileName: sliceFileName,
          timelineStartSec: timelineStart,
          timelineEndSec: timelineEnd,
          spedDurationSec: dur,
          speed: speed,
        ),
      );
    }

    onLog?.call('全部 ${slices.length} 個片段切片完成，準備分段進入審查繞過上傳流水線');
    return slices;
  }
}
