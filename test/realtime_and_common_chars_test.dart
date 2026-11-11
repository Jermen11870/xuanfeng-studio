import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fengling_studio_flutter/services/pinyin_converter_service.dart';
import 'package:fengling_studio_flutter/services/common_chinese_chars.dart';
import 'package:fengling_studio_flutter/widgets/interactive_lyric_grid.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final file = File('assets/jyutping_dict.json');
    if (await file.exists()) {
      final jsonStr = await file.readAsString();
      PinyinConverterService.loadFromRawJson(jsonStr);
    }
  });

  test('CommonChineseChars identifies everyday characters and filter uncommon characters', () {
    expect(CommonChineseChars.isCommon('天'), true);
    expect(CommonChineseChars.isCommon('田'), true);
    expect(CommonChineseChars.isCommon('填'), true);
    expect(CommonChineseChars.isCommon('甜'), true);
    expect(CommonChineseChars.isCommon('車'), true);
    expect(CommonChineseChars.isCommon('嘢'), true);
    expect(CommonChineseChars.isCommon('嘅'), true);

    final options = PinyinConverterService.getHomophoneOptions('田', 'tin4');
    expect(options.isNotEmpty, true);
    for (int i = 0; i < options.take(5).length; i++) {
      expect(CommonChineseChars.isCommon(options[i].char), true);
    }
  });

  testWidgets('Typing Chinese lyrics realtime generates Cantonese pinyin', (tester) async {
    final cnCtrl = HighlightTextEditingController();
    final pyCtrl = HighlightTextEditingController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DualLyricEditor(
          chineseController: cnCtrl,
          pinyinController: pyCtrl,
        ),
      ),
    ));

    // 模擬用戶在中文框輸入「海闊天空」
    cnCtrl.text = '海闊天空';
    await tester.pump();

    // 驗證右邊拼音框是否即時自動生成了拼音
    expect(pyCtrl.text.isNotEmpty, true);
    expect(pyCtrl.text, contains('hoi2'));
    expect(pyCtrl.text, contains('tin1'));
  });
}
