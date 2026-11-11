import 'package:flutter/material.dart';
import '../models/lyric_word_item.dart';
import '../services/pinyin_converter_service.dart';

class SideBySideLyricEditor extends StatefulWidget {
  final String rawLyrics;
  final CantoneseStyle cantoneseStyle;
  final Function(String updatedPinyinLyrics)? onPinyinLyricsChanged;

  const SideBySideLyricEditor({
    super.key,
    required this.rawLyrics,
    this.cantoneseStyle = CantoneseStyle.hkPinyinTone,
    this.onPinyinLyricsChanged,
  });

  @override
  State<SideBySideLyricEditor> createState() => _SideBySideLyricEditorState();
}

class _SideBySideLyricEditorState extends State<SideBySideLyricEditor> {
  List<List<LyricWordItem>> _lines = [];
  int? _selectedWordId;
  LyricWordItem? _selectedWord;
  List<HomophoneOption> _homophones = [];
  final TextEditingController _customCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _parseLyrics();
  }

  @override
  void didUpdateWidget(covariant SideBySideLyricEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawLyrics != widget.rawLyrics || oldWidget.cantoneseStyle != widget.cantoneseStyle) {
      _parseLyrics();
    }
  }

  void _parseLyrics() {
    final rawLines = widget.rawLyrics.split('\n');
    final List<List<LyricWordItem>> parsedLines = [];

    int globalId = 0;
    for (int lineIndex = 0; lineIndex < rawLines.length; lineIndex++) {
      final lineStr = rawLines[lineIndex];
      final List<LyricWordItem> lineWords = [];
      for (int i = 0; i < lineStr.length; i++) {
        final char = lineStr[i];
        if (char == ' ') {
          lineWords.add(LyricWordItem(
            id: globalId++,
            lineIndex: lineIndex,
            hanzi: ' ',
            pinyin: '',
            isChinese: false,
            isSpace: true,
          ));
          continue;
        }

        final isChi = PinyinConverterService.isChinese(char);
        String py = '';
        if (isChi) {
          py = PinyinConverterService.convertToCantonese(char, style: widget.cantoneseStyle).trim();
        } else {
          py = char;
        }

        lineWords.add(LyricWordItem(
          id: globalId++,
          lineIndex: lineIndex,
          hanzi: char,
          pinyin: py,
          isChinese: isChi,
        ));
      }
      parsedLines.add(lineWords);
    }

    _lines = parsedLines;
    _selectedWordId = null;
    _selectedWord = null;
    _homophones = [];
    setState(() {});
  }

  void _selectWord(LyricWordItem word) {
    if (!word.isChinese) return;

    setState(() {
      _selectedWordId = word.id;
      _selectedWord = word;
      _homophones = PinyinConverterService.getHomophoneOptions(word.hanzi, word.pinyin);
      _customCtrl.text = word.pinyin;
    });

    // 若屏幕寬度小於 900px（分欄狀態下可用寬度不足），統一使用底部彈出面板，徹底避免文字被擠壓
    if (MediaQuery.of(context).size.width < 900) {
      _showMobileTonePicker();
    }
  }

  void _showMobileTonePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            margin: const EdgeInsets.all(12),
            child: _buildTonePickerCard(
              isModal: true,
              onUpdated: () => setModalState(() {}),
            ),
          );
        },
      ),
    );
  }

  void _replacePinyin(String newPinyin) {
    if (_selectedWordId == null) return;

    for (final line in _lines) {
      final idx = line.indexWhere((w) => w.id == _selectedWordId);
      if (idx != -1) {
        setState(() {
          // 中文歌詞完全不動，只替代拼音
          line[idx] = line[idx].copyWith(pinyin: newPinyin);
          _selectedWord = line[idx];
          _customCtrl.text = newPinyin;
          _homophones = PinyinConverterService.getHomophoneOptions(line[idx].hanzi, newPinyin);
        });
        break;
      }
    }

    _notifyPinyinChanged();
  }

  void _notifyPinyinChanged() {
    final buffer = StringBuffer();
    for (int l = 0; l < _lines.length; l++) {
      final line = _lines[l];
      for (int w = 0; w < line.length; w++) {
        final word = line[w];
        if (word.isSpace) {
          buffer.write(' ');
        } else if (word.isChinese) {
          buffer.write('${word.pinyin} ');
        } else {
          buffer.write(word.hanzi);
        }
      }
      if (l < _lines.length - 1) {
        buffer.write('\n');
      }
    }
    widget.onPinyinLyricsChanged?.call(buffer.toString().trim());
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty || _lines.every((l) => l.isEmpty)) {
      return const Center(
        child: Text('請先在左側輸入中文歌詞', style: TextStyle(color: Color(0xFF64748B))),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 620;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左右對照主區域 (左側中文歌詞 vs 右側廣東話拼音)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                padding: EdgeInsets.all(isNarrow ? 8 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 欄位標題提示列 (簡潔防重疊)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.translate, size: 13, color: Color(0xFF38BDF8)),
                          SizedBox(width: 4),
                          Text(
                            '中文',
                            style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, size: 11, color: Color(0xFF64748B)),
                          SizedBox(width: 8),
                          Icon(Icons.record_voice_over, size: 13, color: Color(0xFF02AF4A)),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '拼音 (點擊字詞可微調讀音)',
                              style: TextStyle(color: Color(0xFF02AF4A), fontSize: 11, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                // 左右逐行逐字平行排列列表
                Expanded(
                  child: ListView.separated(
                    itemCount: _lines.length,
                    separatorBuilder: (ctx, i) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Divider(color: Color(0xFF1E293B), height: 1),
                    ),
                    itemBuilder: (ctx, lineIndex) {
                      final line = _lines[lineIndex];
                      if (line.isEmpty) {
                        return const SizedBox(height: 20);
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左邊：中文歌詞
                          Expanded(
                            flex: 1,
                            child: Wrap(
                              spacing: 3,
                              runSpacing: 6,
                              children: line.map((w) {
                                if (w.isSpace) return const SizedBox(width: 8);
                                final isSelected = w.id == _selectedWordId;

                                return GestureDetector(
                                  onTap: () => _selectWord(w),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF02AF4A).withValues(alpha: 0.25)
                                          : const Color(0xFF1E293B).withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(6),
                                      // 點擊中文有綠色高亮方框！
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF02AF4A) : Colors.transparent,
                                        width: 1.5,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: const Color(0xFF02AF4A).withValues(alpha: 0.3),
                                                blurRadius: 6,
                                                spreadRadius: 1,
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: Text(
                                      w.hanzi,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? const Color(0xFF34D399) : Colors.white,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          const SizedBox(width: 6),
                          const Padding(
                            padding: EdgeInsets.only(top: 6.0),
                            child: Icon(Icons.arrow_forward, size: 12, color: Color(0xFF475569)),
                          ),
                          const SizedBox(width: 6),

                          // 右邊：廣東話拼音 (帶音調標記)
                          Expanded(
                            flex: 1,
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 6,
                              children: line.map((w) {
                                if (w.isSpace) return const SizedBox(width: 8);
                                final isSelected = w.id == _selectedWordId;

                                return GestureDetector(
                                  onTap: () => _selectWord(w),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF02AF4A).withValues(alpha: 0.25)
                                          : const Color(0xFF1E293B).withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF02AF4A) : Colors.transparent,
                                        width: 1.5,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: const Color(0xFF02AF4A).withValues(alpha: 0.3),
                                                blurRadius: 6,
                                                spreadRadius: 1,
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: Text(
                                      w.pinyin,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // 右邊展開面板 (僅容器寬度足夠時在右側展開，否則底部彈出防擠壓)
        if (_selectedWord != null && !isNarrow) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: _buildTonePickerCard(),
          ),
        ],
      ],
    );
  },
);
}

  Widget _buildTonePickerCard({bool isModal = false, VoidCallback? onUpdated}) {
    if (_selectedWord == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF02AF4A).withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(-2, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題與關閉按鈕
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF02AF4A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '【${_selectedWord!.hanzi}】',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('當前拼音', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    Text(
                      _selectedWord!.pinyin,
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)),
                onPressed: () {
                  if (isModal) {
                    Navigator.of(context).pop();
                  }
                  setState(() {
                    _selectedWordId = null;
                    _selectedWord = null;
                  });
                },
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 20),

          const Row(
            children: [
              Icon(Icons.swap_calls, size: 15, color: Color(0xFFFBBF24)),
              SizedBox(width: 6),
              Text(
                '可選近音字 / 同音字：',
                style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '點選直接替換拼音 · 中文歌詞不動',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
          ),
          const SizedBox(height: 10),

          // 近音字 / 同音字候選按鈕 (最少 5 個選項，顯示【中文】和【拼音】)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Column(
                children: _homophones.map((opt) {
                  final isCurrent = opt.pinyin == _selectedWord!.pinyin || opt.hkPinyin == _selectedWord!.pinyin;
                  final displayPinyin = opt.hkPinyin.isNotEmpty ? opt.hkPinyin : opt.pinyin;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: InkWell(
                      onTap: () {
                        _replacePinyin(displayPinyin);
                        onUpdated?.call();
                        if (isModal) {
                          Navigator.of(context).pop();
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? const Color(0xFF02AF4A).withValues(alpha: 0.2)
                              : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrent ? const Color(0xFF02AF4A) : const Color(0xFF334155),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  opt.char,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  displayPinyin,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: isCurrent ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                                  ),
                                ),
                              ],
                            ),
                            if (isCurrent)
                              const Icon(Icons.check_circle, size: 14, color: Color(0xFF34D399)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 10),

          // 自訂拼音手動輸入
          const Text('自訂此字拼音：', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _customCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: '例: suet3',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final val = _customCtrl.text.trim();
                  if (val.isNotEmpty) {
                    _replacePinyin(val);
                    onUpdated?.call();
                    if (isModal) {
                      Navigator.of(context).pop();
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF02AF4A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                child: const Text('確認', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
