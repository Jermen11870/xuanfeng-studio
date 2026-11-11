import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fengling_studio_flutter/services/pinyin_converter_service.dart';
import 'package:fengling_studio_flutter/models/lyric_word_item.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final file = File('assets/jyutping_dict.json');
    if (await file.exists()) {
      final jsonStr = await file.readAsString();
      PinyinConverterService.loadFromRawJson(jsonStr);
    }
  });

  test('PinyinConverterService produces tone numbers 1-6 correctly', () {
    final raw = '藍天白雲';
    final py = PinyinConverterService.convertToCantonese(raw, style: CantoneseStyle.hkPinyinTone);
    // 字典中：藍 -> lam4, 天 -> tin1, 白 -> bak6, 雲 -> wan4
    expect(py, contains('tin1'));
    expect(py, contains('wan4'));
  });

  test('Pinyin replacement updates only pinyin and leaves chinese untouched without dollar literal bug', () {
    final lines = PinyinConverterService.parseLyricsToLines('藍天白雲', style: CantoneseStyle.hkPinyinTone);
    expect(lines.isNotEmpty, true);
    expect(lines[0].length, 4);

    // 模擬替換「藍」的讀音為「laam5」
    lines[0][0].pinyin = 'laam5';

    final flat = <LyricWordItem>[];
    for (int l = 0; l < lines.length; l++) {
      flat.addAll(lines[l]);
    }
    final rebuilt = PinyinConverterService.rebuildPinyinLyrics(flat);

    // 檢查替換結果
    expect(rebuilt.contains('laam5'), true);
    expect(rebuilt.contains(r'${w.pinyin}'), false);
    expect(rebuilt.contains(r'$'), false);

    // 中文字依然是「藍」
    expect(lines[0][0].hanzi, '藍');
  });
}
