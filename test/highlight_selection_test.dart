import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fengling_studio_flutter/services/pinyin_converter_service.dart';
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

  testWidgets('HighlightTextEditingController builds highlighted spans correctly', (tester) async {
    final ctrl = HighlightTextEditingController(text: '藍天白雲');
    ctrl.setHighlight(const TextRange(start: 1, end: 2)); // 天
    expect(ctrl.highlightRange, const TextRange(start: 1, end: 2));
  });

  testWidgets('DualLyricEditor widget mounts and syncs bidirectional highlight', (tester) async {
    final cnCtrl = HighlightTextEditingController(text: '車田車嚤嚤嚤翼');
    final pyCtrl = HighlightTextEditingController(text: 'che1 tin4 che1 geong1 geong1 geong1 yik6');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DualLyricEditor(
          chineseController: cnCtrl,
          pinyinController: pyCtrl,
        ),
      ),
    ));

    // 模擬在左邊選取「田」(index 1~2)
    cnCtrl.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    await tester.pump();

    // 驗證右邊拼音框是否被設定了 tin4 的高亮 (5 ~ 9)
    expect(pyCtrl.highlightRange, isNotNull);
    expect(pyCtrl.highlightRange!.start, 5);
    expect(pyCtrl.highlightRange!.end, 9);

    // 模擬在右邊選取「yik6」(index 36~40)
    pyCtrl.selection = const TextSelection(baseOffset: 36, extentOffset: 40);
    await tester.pump();

    // 驗證左邊中文框是否被設定了「翼」的高亮 (index 6 ~ 7)
    expect(cnCtrl.highlightRange, isNotNull);
    expect(cnCtrl.highlightRange!.start, 6);
    expect(cnCtrl.highlightRange!.end, 7);
  });
}
