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

  testWidgets('Selecting multiple words highlights all corresponding pinyin tokens', (tester) async {
    final cnCtrl = HighlightTextEditingController(text: '車田車嚤嚤嚤翼\n藍天白雲\n晴空萬里');
    final pyCtrl = HighlightTextEditingController(text: 'che1 tin4 che1 geong1 geong1 geong1 yik6\nlam4 tin1 bak6 wan4\ncing4 hung1 maan6 lei5');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DualLyricEditor(
          chineseController: cnCtrl,
          pinyinController: pyCtrl,
        ),
      ),
    ));

    // 1. 在左邊選取同一行多個字「田車嚤」(index 1 ~ 4)
    cnCtrl.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    await tester.pump();

    // 驗證右邊是否高亮了 tin4 che1 geong1 (index 5 ~ 21)
    expect(pyCtrl.highlightRanges.isNotEmpty, true);
    expect(pyCtrl.highlightRanges.first.start, 5);
    expect(pyCtrl.highlightRanges.first.end, 21);

    // 2. 在左邊跨行選取多句 (選取第 2 句與第 3 句，index 8 ~ 17)
    cnCtrl.selection = const TextSelection(baseOffset: 8, extentOffset: 17);
    await tester.pump();

    // 驗證右邊是否產生了多個跨行高亮區塊 (覆蓋了第 2 行與第 3 行)
    expect(pyCtrl.highlightRanges.length, greaterThanOrEqualTo(2));

    // 3. 反向：在右邊選取多句 (index 41 ~ 83)，驗證左邊是否也即時高亮多個字/多句
    pyCtrl.selection = const TextSelection(baseOffset: 41, extentOffset: 83);
    await tester.pump();

    expect(cnCtrl.highlightRanges.length, greaterThanOrEqualTo(2));
  });
}
