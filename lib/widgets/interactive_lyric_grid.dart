import 'dart:math';
import 'package:flutter/material.dart';
import '../models/lyric_word_item.dart';
import '../services/pinyin_converter_service.dart';

/// 支援多區間文字背景色高亮的 TextEditingController
class HighlightTextEditingController extends TextEditingController {
  List<TextRange> highlightRanges = [];
  Color highlightColor;

  HighlightTextEditingController({
    super.text,
    this.highlightColor = const Color(0xFF02AF4A),
  });

  void setHighlights(List<TextRange> ranges) {
    final validRanges = <TextRange>[];
    final len = text.length;
    for (final r in ranges) {
      if (r.isValid && r.start < r.end && r.start >= 0 && r.end <= len) {
        validRanges.add(r);
      }
    }
    validRanges.sort((a, b) => a.start.compareTo(b.start));

    // 合併重疊或相鄰區間
    final merged = <TextRange>[];
    for (final r in validRanges) {
      if (merged.isEmpty) {
        merged.add(r);
      } else {
        final last = merged.last;
        if (r.start <= last.end) {
          merged[merged.length - 1] = TextRange(
            start: last.start,
            end: r.end > last.end ? r.end : last.end,
          );
        } else {
          merged.add(r);
        }
      }
    }

    if (_areRangesEqual(merged, highlightRanges)) return;
    highlightRanges = merged;
    notifyListeners();
  }

  static bool _areRangesEqual(List<TextRange> a, List<TextRange> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start || a[i].end != b[i].end) return false;
    }
    return true;
  }

  TextRange? get highlightRange => highlightRanges.isNotEmpty ? highlightRanges.first : null;

  void setHighlight(TextRange? range) {
    setSingleHighlight(range);
  }

  void setSingleHighlight(TextRange? range) {
    if (range == null || !range.isValid || range.start >= range.end) {
      clearHighlight();
    } else {
      setHighlights([range]);
    }
  }

  void clearHighlight() {
    if (highlightRanges.isNotEmpty) {
      highlightRanges = [];
      notifyListeners();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final fullText = text;
    if (highlightRanges.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    final children = <TextSpan>[];
    int currentPos = 0;

    for (final range in highlightRanges) {
      final start = range.start.clamp(0, fullText.length);
      final end = range.end.clamp(0, fullText.length);

      if (start > currentPos) {
        children.add(TextSpan(
          text: fullText.substring(currentPos, start),
          style: style,
        ));
      }

      if (end > start) {
        children.add(TextSpan(
          text: fullText.substring(start, end),
          style: (style ?? const TextStyle()).copyWith(
            backgroundColor: highlightColor.withValues(alpha: 0.5),
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ));
      }

      currentPos = end;
    }

    if (currentPos < fullText.length) {
      children.add(TextSpan(
        text: fullText.substring(currentPos),
        style: style,
      ));
    }

    return TextSpan(children: children, style: style);
  }
}

/// 雙輸入框歌詞編輯器：
/// 1. 左右兩邊皆為輸入框，兩邊皆可直接編輯
/// 2. 左邊打字實時自動轉換為帶調廣東話拼音
/// 3. 選取多個字或多句時，另一邊即時全部改變對應文字的背景色
/// 4. 選中單字時，上方提供常用同音/近音字替換候選
class DualLyricEditor extends StatefulWidget {
  final HighlightTextEditingController chineseController;
  final HighlightTextEditingController pinyinController;
  final bool enabled;
  final VoidCallback? onChanged;

  const DualLyricEditor({
    super.key,
    required this.chineseController,
    required this.pinyinController,
    this.enabled = true,
    this.onChanged,
  });

  @override
  State<DualLyricEditor> createState() => _DualLyricEditorState();
}

class _DualLyricEditorState extends State<DualLyricEditor> {
  String _lastChineseText = '';

  // 單字選中時的近音選項狀態
  String? _selectedChar;
  String? _selectedCurrentPinyin;
  int? _selectedLineIdx;
  int? _selectedTokenIdxInLine;
  List<HomophoneOption> _currentHomophones = [];

  bool _isInternalUpdating = false;
  bool _isSyncingHighlight = false;

  @override
  void initState() {
    super.initState();
    _lastChineseText = widget.chineseController.text;
    widget.chineseController.addListener(_onChineseChanged);
    widget.pinyinController.addListener(_onPinyinChanged);
  }

  @override
  void dispose() {
    widget.chineseController.removeListener(_onChineseChanged);
    widget.pinyinController.removeListener(_onPinyinChanged);
    super.dispose();
  }

  void _onChineseChanged() {
    if (_isInternalUpdating) return;

    final currentChinese = widget.chineseController.text;
    // 輸入中文歌詞時，即時實時自動轉換為廣東話拼音 (帶音調)
    if (currentChinese != _lastChineseText) {
      _lastChineseText = currentChinese;
      if (currentChinese.trim().isNotEmpty) {
        final py = PinyinConverterService.convertToCantonese(
          currentChinese,
          style: CantoneseStyle.hkPinyinTone,
        );
        _isInternalUpdating = true;
        widget.pinyinController.text = py;
        _isInternalUpdating = false;
        widget.onChanged?.call();
      } else {
        _isInternalUpdating = true;
        widget.pinyinController.clear();
        _isInternalUpdating = false;
        widget.onChanged?.call();
      }
    }

    // 檢查選取範圍 (支援多個字與多句)，即時高亮另一邊背景色
    final sel = widget.chineseController.selection;
    if (sel.isValid) {
      _syncSelectionFromChinese(sel);
    } else {
      widget.pinyinController.clearHighlight();
    }
  }

  void _onPinyinChanged() {
    if (_isInternalUpdating) return;

    final sel = widget.pinyinController.selection;
    if (sel.isValid) {
      _syncSelectionFromPinyin(sel);
    } else {
      widget.chineseController.clearHighlight();
    }
  }

  /// 從左邊中文選取 (單字/多字/多句) -> 映射到右邊拼音多區間背景高亮
  void _syncSelectionFromChinese(TextSelection sel) {
    if (_isSyncingHighlight) return;
    _isSyncingHighlight = true;
    try {
      _doSyncSelectionFromChinese(sel);
    } finally {
      _isSyncingHighlight = false;
    }
  }

  void _doSyncSelectionFromChinese(TextSelection sel) {
    final cnText = widget.chineseController.text;
    final pyText = widget.pinyinController.text;
    if (cnText.isEmpty || pyText.isEmpty) {
      widget.pinyinController.clearHighlight();
      return;
    }

    int start = sel.start;
    int end = sel.end;
    if (start == end) {
      // 游標點擊：若在字後選取前一字，若在開頭選取後一字
      if (start > 0 && start <= cnText.length) {
        start = start - 1;
      } else if (start < cnText.length) {
        end = start + 1;
      }
    }
    start = start.clamp(0, cnText.length);
    end = end.clamp(0, cnText.length);
    if (start >= end) {
      widget.pinyinController.clearHighlight();
      return;
    }

    final cnLines = cnText.split(RegExp(r'\r?\n'));
    final pyLines = pyText.split(RegExp(r'\r?\n'));

    final pyRanges = <TextRange>[];
    int cnCur = 0;
    int pyCur = 0;

    String? singleSelectedChar;
    String? singleSelectedPinyin;
    int? singleLineIdx;
    int? singleTokenIdx;
    int totalSelectedChars = 0;

    for (int l = 0; l < cnLines.length; l++) {
      final cnLine = cnLines[l];
      final cnLen = cnLine.length;
      final cnLineStart = cnCur;
      final cnLineEnd = cnCur + cnLen;

      final pyLine = l < pyLines.length ? pyLines[l] : '';
      final pyLen = pyLine.length;
      final pyLineStart = pyCur;

      final oStart = max(start, cnLineStart);
      final oEnd = min(end, cnLineEnd);

      if (oStart < oEnd && pyLine.isNotEmpty) {
        final relS = oStart - cnLineStart;
        final relE = oEnd - cnLineStart;

        // 計算重疊區段在該行包含的非空白字符數量
        int tS = 0;
        for (int i = 0; i < relS; i++) {
          if (cnLine[i].trim().isNotEmpty) tS++;
        }
        int tCount = 0;
        for (int i = relS; i < relE; i++) {
          if (cnLine[i].trim().isNotEmpty) tCount++;
        }
        totalSelectedChars += tCount;

        if (tCount > 0) {
          final tE = tS + tCount - 1;
          final pyTokens = RegExp(r'\S+').allMatches(pyLine).toList();

          if (pyTokens.isNotEmpty && tS < pyTokens.length) {
            final tIdxStart = max(0, tS);
            final tIdxEnd = min(pyTokens.length - 1, max(tIdxStart, tE));

            final tokStart = pyTokens[tIdxStart];
            final tokEnd = pyTokens[tIdxEnd];

            pyRanges.add(TextRange(
              start: pyLineStart + tokStart.start,
              end: pyLineStart + tokEnd.end,
            ));

            if (tCount == 1 && totalSelectedChars == 1) {
              for (int i = relS; i < relE; i++) {
                if (cnLine[i].trim().isNotEmpty) {
                  singleSelectedChar = cnLine[i];
                  break;
                }
              }
              singleSelectedPinyin = tokStart.group(0);
              singleLineIdx = l;
              singleTokenIdx = tIdxStart;
            }
          }
        }
      }

      cnCur += cnLen + 1;
      pyCur += pyLen + 1;
    }

    // 將右邊所有對應拼音區段設為背景高亮
    widget.pinyinController.setHighlights(pyRanges);

    // 若僅選取單個字，展示近音字候選；若選取多字/多句，收起單字候選以保畫面整潔
    if (totalSelectedChars == 1 && singleSelectedChar != null && singleSelectedPinyin != null) {
      setState(() {
        _selectedChar = singleSelectedChar;
        _selectedCurrentPinyin = singleSelectedPinyin;
        _selectedLineIdx = singleLineIdx;
        _selectedTokenIdxInLine = singleTokenIdx;
        _currentHomophones = PinyinConverterService.getHomophoneOptions(singleSelectedChar!, singleSelectedPinyin!);
      });
    } else {
      if (_selectedChar != null) {
        setState(() {
          _selectedChar = null;
          _selectedCurrentPinyin = null;
          _currentHomophones = [];
        });
      }
    }
  }

  /// 從右邊拼音選取 (多詞/多行) -> 映射到左邊中文多區間背景高亮
  void _syncSelectionFromPinyin(TextSelection sel) {
    if (_isSyncingHighlight) return;
    _isSyncingHighlight = true;
    try {
      _doSyncSelectionFromPinyin(sel);
    } finally {
      _isSyncingHighlight = false;
    }
  }

  void _doSyncSelectionFromPinyin(TextSelection sel) {
    final cnText = widget.chineseController.text;
    final pyText = widget.pinyinController.text;
    if (cnText.isEmpty || pyText.isEmpty) {
      widget.chineseController.clearHighlight();
      return;
    }

    int start = sel.start;
    int end = sel.end;
    if (start == end) {
      if (start > 0 && start <= pyText.length) {
        start = start - 1;
      } else if (start < pyText.length) {
        end = start + 1;
      }
    }
    start = start.clamp(0, pyText.length);
    end = end.clamp(0, pyText.length);
    if (start >= end) {
      widget.chineseController.clearHighlight();
      return;
    }

    final cnLines = cnText.split(RegExp(r'\r?\n'));
    final pyLines = pyText.split(RegExp(r'\r?\n'));

    final cnRanges = <TextRange>[];
    int cnCur = 0;
    int pyCur = 0;

    String? singleSelectedChar;
    String? singleSelectedPinyin;
    int? singleLineIdx;
    int? singleTokenIdx;
    int totalSelectedTokens = 0;

    for (int l = 0; l < pyLines.length; l++) {
      final pyLine = pyLines[l];
      final pyLen = pyLine.length;
      final pyLineStart = pyCur;
      final pyLineEnd = pyCur + pyLen;

      final cnLine = l < cnLines.length ? cnLines[l] : '';
      final cnLen = cnLine.length;
      final cnLineStart = cnCur;

      final oStart = max(start, pyLineStart);
      final oEnd = min(end, pyLineEnd);

      if (oStart < oEnd && cnLine.isNotEmpty) {
        final relS = oStart - pyLineStart;
        final relE = oEnd - pyLineStart;

        final pyTokens = RegExp(r'\S+').allMatches(pyLine).toList();
        final tokIndices = <int>[];
        for (int t = 0; t < pyTokens.length; t++) {
          final tok = pyTokens[t];
          if (max(tok.start, relS) < min(tok.end, relE) || (relS <= tok.start && relE >= tok.end)) {
            tokIndices.add(t);
          }
        }
        if (tokIndices.isEmpty) {
          for (int t = 0; t < pyTokens.length; t++) {
            if (pyTokens[t].start <= relS && relS <= pyTokens[t].end) {
              tokIndices.add(t);
              break;
            }
          }
        }

        if (tokIndices.isNotEmpty) {
          totalSelectedTokens += tokIndices.length;
          final tFirst = tokIndices.first;
          final tLast = tokIndices.last;

          final nonSpaces = <int>[];
          for (int i = 0; i < cnLine.length; i++) {
            if (cnLine[i].trim().isNotEmpty) nonSpaces.add(i);
          }

          if (nonSpaces.isNotEmpty && tFirst < nonSpaces.length) {
            final cStart = nonSpaces[tFirst];
            final cEndIdx = min(nonSpaces.length - 1, tLast);
            final cEnd = nonSpaces[cEndIdx] + 1;

            cnRanges.add(TextRange(
              start: cnLineStart + cStart,
              end: cnLineStart + cEnd,
            ));

            if (tokIndices.length == 1 && totalSelectedTokens == 1) {
              singleSelectedChar = cnLine[cStart];
              singleSelectedPinyin = pyTokens[tFirst].group(0);
              singleLineIdx = l;
              singleTokenIdx = tFirst;
            }
          }
        }
      }

      cnCur += cnLen + 1;
      pyCur += pyLen + 1;
    }

    // 將左邊所有對應中文區段設為背景高亮
    widget.chineseController.setHighlights(cnRanges);

    if (totalSelectedTokens == 1 && singleSelectedChar != null && singleSelectedPinyin != null) {
      setState(() {
        _selectedChar = singleSelectedChar;
        _selectedCurrentPinyin = singleSelectedPinyin;
        _selectedLineIdx = singleLineIdx;
        _selectedTokenIdxInLine = singleTokenIdx;
        _currentHomophones = PinyinConverterService.getHomophoneOptions(singleSelectedChar!, singleSelectedPinyin!);
      });
    } else {
      if (_selectedChar != null) {
        setState(() {
          _selectedChar = null;
          _selectedCurrentPinyin = null;
          _currentHomophones = [];
        });
      }
    }
  }

  /// 替換選中字的拼音 (左側中文完全不動，僅替換右邊對應位置的拼音)
  void _replaceSelectedPinyin(String newPinyin) {
    if (_selectedLineIdx == null || _selectedTokenIdxInLine == null) return;

    final pyText = widget.pinyinController.text;
    final pyLines = pyText.split(RegExp(r'\r?\n'));
    if (_selectedLineIdx! >= pyLines.length) return;

    final line = pyLines[_selectedLineIdx!];
    final tokens = RegExp(r'\S+').allMatches(line).toList();
    if (_selectedTokenIdxInLine! >= tokens.length) return;

    final targetToken = tokens[_selectedTokenIdxInLine!];
    final newLine = line.substring(0, targetToken.start) +
        newPinyin +
        line.substring(targetToken.end);
    pyLines[_selectedLineIdx!] = newLine;

    final updatedPinyin = pyLines.join('\n');

    _isInternalUpdating = true;
    widget.pinyinController.text = updatedPinyin;
    _isInternalUpdating = false;

    // 更新右側高亮位置至新拼音
    int lineStart = 0;
    for (int i = 0; i < _selectedLineIdx!; i++) {
      lineStart += pyLines[i].length + 1;
    }
    final newHighlightStart = lineStart + targetToken.start;
    final newHighlightEnd = newHighlightStart + newPinyin.length;
    widget.pinyinController.setSingleHighlight(TextRange(start: newHighlightStart, end: newHighlightEnd));

    setState(() {
      _selectedCurrentPinyin = newPinyin;
      if (_selectedChar != null) {
        _currentHomophones = PinyinConverterService.getHomophoneOptions(_selectedChar!, newPinyin);
      }
    });

    widget.onChanged?.call();
  }

  /// 一鍵將中文歌詞轉為廣東話拼音 (帶音調 1-6)
  void convertToCantonese() {
    final raw = widget.chineseController.text;
    if (raw.trim().isEmpty) return;

    final py = PinyinConverterService.convertToCantonese(raw, style: CantoneseStyle.hkPinyinTone);
    _isInternalUpdating = true;
    widget.pinyinController.text = py;
    _isInternalUpdating = false;

    widget.chineseController.clearHighlight();
    widget.pinyinController.clearHighlight();
    setState(() {
      _selectedChar = null;
      _selectedCurrentPinyin = null;
    });

    widget.onChanged?.call();
  }

  /// 一鍵將中文歌詞轉為國語拼音
  void convertToMandarin() {
    final raw = widget.chineseController.text;
    if (raw.trim().isEmpty) return;

    final py = PinyinConverterService.convertToMandarin(raw, style: MandarinStyle.withToneMark);
    _isInternalUpdating = true;
    widget.pinyinController.text = py;
    _isInternalUpdating = false;

    widget.chineseController.clearHighlight();
    widget.pinyinController.clearHighlight();
    setState(() {
      _selectedChar = null;
      _selectedCurrentPinyin = null;
    });

    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final hasChinese = widget.chineseController.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 頂部整合功能列
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.compare_arrows, color: Color(0xFF02AF4A), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      MediaQuery.of(context).size.width < 700 ? '雙邊歌詞編輯器' : '雙邊歌詞編輯器 (選取多字/多句即時聯動 · 鍵入轉拼音)',
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    // 轉廣東話拼音 (帶音調)
                    ElevatedButton.icon(
                      onPressed: widget.enabled && hasChinese ? convertToCantonese : null,
                      icon: const Icon(Icons.record_voice_over, size: 14),
                      label: const Text('轉廣東話拼音 (帶音調)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF02AF4A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    // 轉國語拼音
                    OutlinedButton.icon(
                      onPressed: widget.enabled && hasChinese ? convertToMandarin : null,
                      icon: const Icon(Icons.translate, size: 14, color: Color(0xFF38BDF8)),
                      label: const Text('轉國語拼音', style: TextStyle(color: Color(0xFF38BDF8))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF0284C7)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    // 清空按鈕
                    IconButton(
                      tooltip: '清空兩邊歌詞',
                      icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                      onPressed: widget.enabled
                          ? () {
                              _isInternalUpdating = true;
                              widget.chineseController.clear();
                              widget.pinyinController.clear();
                              widget.chineseController.clearHighlight();
                              widget.pinyinController.clearHighlight();
                              _isInternalUpdating = false;
                              setState(() {
                                _selectedChar = null;
                                _selectedCurrentPinyin = null;
                              });
                              widget.onChanged?.call();
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 選字即時近音字候選橫條 (選取單字時自動展開，展示常用同音/近音字)
          if (_selectedChar != null && _selectedCurrentPinyin != null && _currentHomophones.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF0B132B),
                border: Border(bottom: BorderSide(color: Color(0xFF02AF4A), width: 1.5)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF02AF4A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _selectedChar!,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '目前音: $_selectedCurrentPinyin',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  const Text('常用字候選替換：', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _currentHomophones.take(8).map((opt) {
                          final pinyinVal = opt.hkPinyin.isNotEmpty ? opt.hkPinyin : opt.pinyin;
                          final isCurrent = pinyinVal == _selectedCurrentPinyin;

                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text('${opt.char} $pinyinVal (${opt.tag})'),
                              labelStyle: TextStyle(
                                color: isCurrent ? const Color(0xFF34D399) : Colors.white,
                                fontSize: 11,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              ),
                              backgroundColor: isCurrent
                                  ? const Color(0xFF02AF4A).withValues(alpha: 0.25)
                                  : const Color(0xFF1E293B),
                              side: BorderSide(
                                color: isCurrent ? const Color(0xFF02AF4A) : const Color(0xFF334155),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              onPressed: () => _replaceSelectedPinyin(pinyinVal),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                    tooltip: '關閉候選列',
                    onPressed: () {
                      widget.chineseController.clearHighlight();
                      widget.pinyinController.clearHighlight();
                      setState(() {
                        _selectedChar = null;
                        _selectedCurrentPinyin = null;
                      });
                    },
                  ),
                ],
              ),
            ),

          // 核心雙輸入框區域 (左右並排，多行寬闊視野)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左側：中文歌詞輸入框
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.edit_note, size: 15, color: Color(0xFF34D399)),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '中文歌詞 (左邊 · 可直接編輯 · 選多字/多句即時高亮右側)',
                              style: TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: widget.chineseController,
                        enabled: widget.enabled,
                        maxLines: 9,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.6,
                          fontFamily: 'sans-serif',
                        ),
                        decoration: InputDecoration(
                          hintText: '在此輸入或貼上中文歌詞...\n選取多個字或多句，右邊即時同步變色！',
                          hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF02AF4A), width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // 右側：拼音輸入框
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.music_note, size: 15, color: Color(0xFF38BDF8)),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '廣東話拼音 (右邊 · 帶音調 · 可直接編輯 · 提交 Suno)',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: widget.pinyinController,
                        enabled: widget.enabled,
                        maxLines: 9,
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 14,
                          height: 1.6,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: '自動生成或在此直接手動修改拼音...\n選取多詞或多句，左邊即時同步變色！',
                          hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF0B132B),
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF1E293B)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
