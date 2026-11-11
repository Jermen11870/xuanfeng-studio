import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fengling_studio_flutter/services/audio_warp_processor.dart';
import 'package:fengling_studio_flutter/services/suno_studio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('音訊 4X 防審查切片與雲端合併測試', () {
    late Directory tempDir;
    late String testAudioPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('warp_test_');
      testAudioPath = '${tempDir.path}/test_25s.wav';

      // 使用 ffmpeg 快速生成 25 秒正弦波測試音訊
      final genRes = await Process.run('ffmpeg', [
        '-y',
        '-f', 'lavfi',
        '-i', 'sine=frequency=440:duration=25',
        '-ar', '44100',
        '-ac', '2',
        testAudioPath,
      ]);
      expect(genRes.exitCode, 0, reason: '生成測試音訊失敗');
      expect(await File(testAudioPath).exists(), isTrue);
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('4X 變速壓縮與定長切片演算法驗證', () async {
      final workDir = Directory('${tempDir.path}/slices');
      await workDir.create(recursive: true);

      final slices = await AudioWarpProcessor.processAndSlice4X(
        inputPath: testAudioPath,
        originalDurationSec: 25.0,
        workDir: workDir,
        speed: 4.0,
        sliceSec: 10.0,
        onLog: (msg) {
          // ignore: avoid_print
          print('[TestLog] $msg');
        },
      );

      // 25 秒 4X 變速後為 6.25 秒 (< 10 秒)，應恰好切出 1 個片段
      expect(slices.isNotEmpty, isTrue);
      expect(slices.length, 1);
      final slice1 = slices.first;
      expect(slice1.index, 1);
      expect(await File(slice1.filePath).exists(), isTrue);
      expect(await File(slice1.filePath).length(), greaterThan(1000));
      expect(slice1.spedDurationSec, closeTo(6.25, 0.1));
      expect(slice1.timelineEndSec, closeTo(25.0, 0.1));
    });

    test('多片段定長切片 (50秒音訊 ➔ 4X 後 12.5秒 ➔ 切片)', () async {
      final audio50sPath = '${tempDir.path}/test_50s.wav';
      await Process.run('ffmpeg', [
        '-y',
        '-f', 'lavfi',
        '-i', 'sine=frequency=440:duration=50',
        '-ar', '44100',
        '-ac', '2',
        audio50sPath,
      ]);

      final workDir = Directory('${tempDir.path}/slices_50s');
      await workDir.create(recursive: true);

      final slices = await AudioWarpProcessor.processAndSlice4X(
        inputPath: audio50sPath,
        originalDurationSec: 50.0,
        workDir: workDir,
        speed: 4.0,
        sliceSec: 10.0,
      );

      expect(slices.isNotEmpty, isTrue);
      for (final s in slices) {
        expect(await File(s.filePath).exists(), isTrue);
        expect(await File(s.filePath).length(), greaterThan(1000));
      }
    });

    test('Warp 緻密時間軸還原標記演算法正確性', () {
      final markers = SunoStudioService.buildDenseWarpMarkers(10.0, 40.0, 2.0);
      expect(markers.isNotEmpty, isTrue);
      expect(markers.containsKey("0"), isTrue);
      expect(markers["0"], 0);
      // 尾部標記應鎖定在 10.0 (原速 40秒 * 2 bps = 80 beats)
      expect(markers.containsKey("10.0"), isTrue);
      expect(markers["10.0"], 80.0);
    });

    test('Downbeats 節奏拍子計算驗證', () {
      final beats = SunoStudioService.calculateDownbeats(2.0, 0, 16);
      expect(beats.length, 16);
      expect(beats[0], [0.0, 1]);
      expect(beats[1], [0.5, 2]);
      expect(beats[2], [1.0, 3]);
      expect(beats[3], [1.5, 4]);
      expect(beats[4], [2.0, 1]);
    });
  });
}
