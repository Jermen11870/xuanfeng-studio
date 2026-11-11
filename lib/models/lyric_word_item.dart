class HomophoneOption {
  final String char;
  final String pinyin;
  final String hkPinyin;
  final String tag; // '同音' 或 '近音'

  HomophoneOption({
    required this.char,
    required this.pinyin,
    required this.hkPinyin,
    this.tag = '同音',
  });
}

class LyricWordItem {
  final int id;
  final int lineIndex;
  final String hanzi;
  String pinyin;
  final bool isChinese;
  final bool isNewline;
  final bool isSpace;

  LyricWordItem({
    required this.id,
    this.lineIndex = 0,
    required this.hanzi,
    required this.pinyin,
    this.isChinese = true,
    this.isNewline = false,
    this.isSpace = false,
  });

  LyricWordItem copyWith({
    String? pinyin,
  }) {
    return LyricWordItem(
      id: id,
      lineIndex: lineIndex,
      hanzi: hanzi,
      pinyin: pinyin ?? this.pinyin,
      isChinese: isChinese,
      isNewline: isNewline,
      isSpace: isSpace,
    );
  }
}
