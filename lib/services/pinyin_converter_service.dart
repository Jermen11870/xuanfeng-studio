import 'common_chinese_chars.dart';
import '../models/lyric_word_item.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:lpinyin/lpinyin.dart';

enum CantoneseStyle {
  hkPinyinTone,         // 港式口音帶數字聲調 (例：suet3, cheung4, yuet6) · SUNO 唱音最準
  jyutpingTone,         // 標準粵拼數字聲調 (例：syut3, coeng4, jyut6) · SUNO 官方相容
  hkPinyinSuperscript,  // 港式口音上標聲調 (例：suet³, cheung⁴, yuet⁶)
  jyutpingSuperscript,  // 標準粵拼上標聲調 (例：syut³, coeng⁴, jyut⁶)
  hkPinyinNoTone,       // 港式口音純音節無調 (例：suet, cheung, yuet)
}

enum MandarinStyle {
  withToneMark,   // 帶聲調符號 (例：hán yè lǐ)
  withToneNum,    // 帶數字聲調 (例：han2 ye4 li3)
  withoutTone,    // 純拼音字母 (例：han ye li)
}

enum PinyinDisplayMode {
  pinyinOnly,     // 純拼音 (推薦上傳給 SUNO)
  rubyStyle,      // 漢字(拼音) 內嵌模式
  sideBySide,     // 上下並排 / 雙行對照
}

class PinyinConverterService {
  static final Map<String, String> _jyutpingDict = {};
  static final Map<String, List<String>> _pinyinToChars = {};
  static bool _isLoaded = false;

  /// 初始化載入 20,800+ 字符粵語字典
  static Future<void> init() async {
    if (_isLoaded) return;
    try {
      final jsonStr = await rootBundle.loadString('assets/jyutping_dict.json');
      loadFromRawJson(jsonStr);
    } catch (e) {
      // 字典備用或已載入
    }
  }

  /// 支援直接載入 JSON 字典資料
  static void loadFromRawJson(String jsonStr) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      data.forEach((k, v) {
        final py = v.toString();
        _jyutpingDict[k] = py;
        _pinyinToChars.putIfAbsent(py, () => []).add(k);
      });
      _isLoaded = true;
    } catch (_) {}
  }

  /// 檢查字元是否為漢字
  static bool isChinese(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    return (code >= 0x4E00 && code <= 0x9FA5) ||
           (code >= 0x3400 && code <= 0x4DBF) ||
           (code >= 0x20000 && code <= 0x2A6DF);
  }

  /// 獲取單個字的粵拼 (原形帶數字聲調，如 gam1, tin1, ngo5)
  static String getCharJyutping(String char) {
    return _jyutpingDict[char] ?? '';
  }

  /// 將標準粵拼轉換為「港式口音廣東話拼音」，並且嚴格保留 1-6 音調供 Suno 唱音
  static String convertToHkPinyin(String jyutping, {String toneStyle = 'number'}) {
    if (jyutping.isEmpty) return '';
    final reg = RegExp(r'^([a-z]+)([1-6])?$', caseSensitive: false);
    final match = reg.firstMatch(jyutping.toLowerCase());
    if (match == null) return jyutping;

    final base = match.group(1)!;
    final tone = match.group(2) ?? '';

    // 特殊全音節港式直接對照
    const exactMap = {
      'jyut': 'yuet',
      'heoi': 'hui',
      'seoi': 'shui',
      'ceoi': 'tsui',
      'geoi': 'kui',
      'neoi': 'lui',
      'leoi': 'lui',
      'deoi': 'tui',
      'teoi': 'tui',
      'zeon': 'chun',
      'ceon': 'chun',
      'syun': 'suen',
      'syut': 'suet',
      'zyun': 'chuen',
      'cyun': 'chuen',
      'jyun': 'yuen',
      'gwo': 'gwo',
      'gwa': 'gwa',
      'gwong': 'kwong',
      'kwong': 'kwong',
      'ng': 'ng',
      'm': 'm',
    };

    String p;
    if (exactMap.containsKey(base)) {
      p = exactMap[base]!;
    } else {
      p = base;
      p = p.replaceAll('oeng', 'eung');
      p = p.replaceAll('oe', 'eu');
      p = p.replaceAll('eoi', 'ui');
      p = p.replaceAll('eon', 'un');
      p = p.replaceAll('eot', 'ut');
      p = p.replaceAll('syut', 'suet');
      p = p.replaceAll('syun', 'suen');
      p = p.replaceAll('yu', 'yue');
      p = p.replaceAll('aa', 'a');
      p = p.replaceAll('ung', 'ong');
      p = p.replaceAll('uk', 'ok');

      if (p.startsWith('jy')) {
        p = 'y${p.substring(2)}';
      } else if (p.startsWith('j')) {
        p = 'y${p.substring(1)}';
      } else if (p.startsWith('z') || p.startsWith('c')) {
        p = 'ch${p.substring(1)}';
      }
    }

    const toneMap = {'1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶'};
    if (toneStyle == 'number' && tone.isNotEmpty) {
      return '$p$tone';
    } else if (toneStyle == 'superscript' && tone.isNotEmpty) {
      return '$p${toneMap[tone] ?? tone}';
    } else if (toneStyle == 'none') {
      return p;
    }
    return tone.isNotEmpty ? '$p$tone' : p;
  }

  /// 轉換歌詞為廣東話拼音 (預設完整包含 1-6 數字音調，保障 SUNO 發音精準)
  static String convertToCantonese(
    String text, {
    CantoneseStyle style = CantoneseStyle.hkPinyinTone,
    PinyinDisplayMode mode = PinyinDisplayMode.pinyinOnly,
  }) {
    final lines = text.split(RegExp(r'\r?\n'));
    final resultLines = <String>[];

    for (final line in lines) {
      if (line.trim().isEmpty) {
        resultLines.add('');
        continue;
      }

      if (mode == PinyinDisplayMode.rubyStyle) {
        final buffer = StringBuffer();
        for (int i = 0; i < line.length; i++) {
          final c = line[i];
          if (isChinese(c)) {
            final raw = getCharJyutping(c);
            final p = _formatCantonesePinyin(raw, style);
            if (p.isNotEmpty) {
              buffer.write('$c($p)');
            } else {
              buffer.write(c);
            }
          } else {
            buffer.write(c);
          }
        }
        resultLines.add(buffer.toString());
      } else if (mode == PinyinDisplayMode.sideBySide) {
        final pinyinBuffer = StringBuffer();
        for (int i = 0; i < line.length; i++) {
          final c = line[i];
          if (isChinese(c)) {
            final raw = getCharJyutping(c);
            final p = _formatCantonesePinyin(raw, style);
            pinyinBuffer.write(p.isNotEmpty ? '$p ' : '$c ');
          } else if (c == ' ') {
            pinyinBuffer.write('  ');
          } else {
            pinyinBuffer.write('$c ');
          }
        }
        resultLines.add(line);
        resultLines.add(pinyinBuffer.toString().trimRight());
      } else {
        // pinyinOnly
        final pinyinBuffer = StringBuffer();
        for (int i = 0; i < line.length; i++) {
          final c = line[i];
          if (isChinese(c)) {
            final raw = getCharJyutping(c);
            final p = _formatCantonesePinyin(raw, style);
            pinyinBuffer.write(p.isNotEmpty ? '$p ' : '$c ');
          } else if (c == ' ') {
            pinyinBuffer.write(' ');
          } else {
            pinyinBuffer.write(c);
          }
        }
        resultLines.add(pinyinBuffer.toString().trim());
      }
    }

    return resultLines.join('\n');
  }

  static String _formatCantonesePinyin(String rawJyutping, CantoneseStyle style) {
    if (rawJyutping.isEmpty) return '';
    const toneMap = {'1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶'};

    switch (style) {
      case CantoneseStyle.hkPinyinTone:
        return convertToHkPinyin(rawJyutping, toneStyle: 'number');
      case CantoneseStyle.jyutpingTone:
        return rawJyutping; // 標準數字調，如 gam1, tin1
      case CantoneseStyle.hkPinyinSuperscript:
        return convertToHkPinyin(rawJyutping, toneStyle: 'superscript');
      case CantoneseStyle.jyutpingSuperscript:
        final reg = RegExp(r'^([a-z]+)([1-6])?$', caseSensitive: false);
        final m = reg.firstMatch(rawJyutping);
        if (m != null) {
          final base = m.group(1)!;
          final tone = m.group(2) ?? '';
          return '$base${toneMap[tone] ?? tone}';
        }
        return rawJyutping;
      case CantoneseStyle.hkPinyinNoTone:
        return convertToHkPinyin(rawJyutping, toneStyle: 'none');
    }
  }

  /// 轉換歌詞為國語拼音
  static String convertToMandarin(
    String text, {
    MandarinStyle style = MandarinStyle.withToneMark,
    PinyinDisplayMode mode = PinyinDisplayMode.pinyinOnly,
  }) {
    PinyinFormat format;
    switch (style) {
      case MandarinStyle.withToneMark:
        format = PinyinFormat.WITH_TONE_MARK;
        break;
      case MandarinStyle.withToneNum:
        format = PinyinFormat.WITH_TONE_NUMBER;
        break;
      case MandarinStyle.withoutTone:
        format = PinyinFormat.WITHOUT_TONE;
        break;
    }

    final lines = text.split(RegExp(r'\r?\n'));
    final resultLines = <String>[];

    for (final line in lines) {
      if (line.trim().isEmpty) {
        resultLines.add('');
        continue;
      }

      if (mode == PinyinDisplayMode.rubyStyle) {
        final buffer = StringBuffer();
        for (int i = 0; i < line.length; i++) {
          final c = line[i];
          if (isChinese(c)) {
            final p = PinyinHelper.getPinyin(c, separator: '', format: format);
            buffer.write('$c($p)');
          } else {
            buffer.write(c);
          }
        }
        resultLines.add(buffer.toString());
      } else if (mode == PinyinDisplayMode.sideBySide) {
        final pinyin = PinyinHelper.getPinyin(line, separator: ' ', format: format);
        resultLines.add(line);
        resultLines.add(pinyin);
      } else {
        final pinyin = PinyinHelper.getPinyin(line, separator: ' ', format: format);
        resultLines.add(pinyin);
      }
    }

    return resultLines.join('\n');
  }

  /// 將歌詞按行解析為二維行列表，供左右對照顯示
  static List<List<LyricWordItem>> parseLyricsToLines(
    String text, {
    CantoneseStyle style = CantoneseStyle.hkPinyinTone,
  }) {
    final rawLines = text.split(RegExp(r'\r?\n'));
    final List<List<LyricWordItem>> lines = [];
    int idCounter = 0;

    for (int l = 0; l < rawLines.length; l++) {
      final lineStr = rawLines[l];
      final List<LyricWordItem> lineWords = [];

      for (int i = 0; i < lineStr.length; i++) {
        final char = lineStr[i];
        if (char == ' ') {
          lineWords.add(LyricWordItem(
            id: idCounter++,
            lineIndex: l,
            hanzi: ' ',
            pinyin: '',
            isChinese: false,
            isSpace: true,
          ));
          continue;
        }

        if (isChinese(char)) {
          final raw = getCharJyutping(char);
          final py = _formatCantonesePinyin(raw, style);
          lineWords.add(LyricWordItem(
            id: idCounter++,
            lineIndex: l,
            hanzi: char,
            pinyin: py.isNotEmpty ? py : char,
            isChinese: true,
          ));
        } else {
          lineWords.add(LyricWordItem(
            id: idCounter++,
            lineIndex: l,
            hanzi: char,
            pinyin: char,
            isChinese: false,
          ));
        }
      }
      lines.add(lineWords);
    }
    return lines;
  }

  /// 相容一維清單方法
  static List<LyricWordItem> parseLyricsToWords(
    String text, {
    CantoneseStyle style = CantoneseStyle.hkPinyinTone,
  }) {
    final lines = parseLyricsToLines(text, style: style);
    final List<LyricWordItem> flat = [];
    for (int i = 0; i < lines.length; i++) {
      flat.addAll(lines[i]);
      if (i < lines.length - 1) {
        flat.add(LyricWordItem(
          id: -1 - i,
          lineIndex: i,
          hanzi: '\n',
          pinyin: '',
          isChinese: false,
          isNewline: true,
        ));
      }
    }
    return flat;
  }

  /// 從 LyricWordItem 清單重建完整的拼音歌詞文字 (可直接上傳 Suno)
  static String rebuildPinyinLyrics(List<LyricWordItem> words) {
    final buffer = StringBuffer();
    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.isNewline) {
        buffer.write('\n');
      } else if (w.isSpace) {
        buffer.write(' ');
      } else if (w.isChinese) {
        buffer.write(w.pinyin.isNotEmpty ? '${w.pinyin} ' : '${w.hanzi} ');
      } else {
        buffer.write(w.hanzi);
      }
    }
    return buffer.toString().trim();
  }

  /// 檢索同音字與近音字建議 (保證最少 8-15 個選項，顯示【中文】與【拼音】)
  static List<HomophoneOption> getHomophoneOptions(String char, String currentPinyin) {
    final List<HomophoneOption> options = [];
    final seenChars = <String>{char};

    String rawJyutping = getCharJyutping(char);
    if (rawJyutping.isEmpty) {
      rawJyutping = currentPinyin.toLowerCase();
    }

    // 1. 同音同調字 (絕對同音) - 嚴格優先挑選常用字
    final sameSoundList = _pinyinToChars[rawJyutping] ?? [];
    final commonSameList = sameSoundList.where((c) => CommonChineseChars.isCommon(c)).toList();
    final candidateSame = commonSameList.isNotEmpty ? commonSameList : sameSoundList;

    for (final c in candidateSame) {
      if (!seenChars.contains(c)) {
        seenChars.add(c);
        final hk = convertToHkPinyin(rawJyutping, toneStyle: 'number');
        options.add(HomophoneOption(
          char: c,
          pinyin: rawJyutping,
          hkPinyin: hk,
          tag: '同音',
        ));
        if (options.length >= 8) break;
      }
    }

    // 2. 近音字：同音節不同聲調 (1-6 調) - 嚴格優先挑選常用字
    final base = rawJyutping.replaceAll(RegExp(r'[1-6]'), '');
    final curTone = rawJyutping.isNotEmpty && '123456'.contains(rawJyutping[rawJyutping.length - 1])
        ? rawJyutping[rawJyutping.length - 1]
        : '';

    for (final tone in ['1', '2', '3', '4', '5', '6']) {
      if (tone != curTone) {
        final altPy = '$base$tone';
        final altList = _pinyinToChars[altPy] ?? [];
        final commonAltList = altList.where((c) => CommonChineseChars.isCommon(c)).toList();
        
        for (final c in commonAltList) {
          if (!seenChars.contains(c)) {
            seenChars.add(c);
            final hk = convertToHkPinyin(altPy, toneStyle: 'number');
            options.add(HomophoneOption(
              char: c,
              pinyin: altPy,
              hkPinyin: hk,
              tag: '近音(調$tone)',
            ));
            if (options.length >= 16) break;
          }
        }
        if (options.length >= 16) break;
      }
    }

    return options;
  }
}
