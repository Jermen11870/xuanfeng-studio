import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/fold_utils.dart';
import '../services/pinyin_converter_service.dart';
import '../widgets/side_by_side_lyric_editor.dart';

class LyricsPinyinView extends StatefulWidget {
  final void Function(String lyrics)? onApplyToUpload;

  const LyricsPinyinView({super.key, this.onApplyToUpload});

  @override
  State<LyricsPinyinView> createState() => _LyricsPinyinViewState();
}

class _LyricsPinyinViewState extends State<LyricsPinyinView> {
  // 0: 純文字/雙行結果, 1: 逐字精修對照
  int _viewMode = 0;
  // 手機版分頁索引 (0: 中文原詞, 1: 拼音結果, 2: 上下並列總覽)
  int _mobileTab = 0;

  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();

  CantoneseStyle _cantoneseStyle = CantoneseStyle.hkPinyinTone;
  MandarinStyle _mandarinStyle = MandarinStyle.withToneMark;
  PinyinDisplayMode _displayMode = PinyinDisplayMode.pinyinOnly;

  String _lastConversionType = 'cantonese'; // 'cantonese' 或 'mandarin'

  // 預設經典歌詞範本供快速測試
  final List<Map<String, String>> _presets = [
    {
      'title': '海闊天空 (Beyond)',
      'lyrics': '今天我 寒夜裏看雪飄過\n懷著冷卻了的心窩漂遠方\n風雨裏追趕 霧裏分不清影蹤\n天空海闊你與我 可會變\n\n原諒我這一生不羈放縱愛自由\n也會怕有一天會跌倒\n背棄了理想 誰人都可以\n哪會怕有一天只你共我'
    },
    {
      'title': '傾城 (陳奕迅)',
      'lyrics': '熱情就算 熄滅了\n分手這一晚 也重要\n甜言蜜語 崩潰了\n仍憑佛偈 支撐了\n\n瓊樓玉宇 倒塌了\n誰又料到 我痛哭了'
    },
    {
      'title': '富士山下 (陳奕迅)',
      'lyrics': '攔路雨偏似雪花 白朗峰的烽煙人間昇華\n原諒我不再送花 傷口應要結疤\n花瓣飄落 誰又會害怕'
    }
  ];

  @override
  void initState() {
    super.initState();
    PinyinConverterService.init();
    _inputController.text = _presets[0]['lyrics']!;
    _doConvert(type: 'cantonese');
  }

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  void _doConvert({String? type}) {
    final t = type ?? _lastConversionType;
    _lastConversionType = t;
    final text = _inputController.text;

    if (text.trim().isEmpty) {
      _outputController.text = '';
      setState(() {});
      return;
    }

    if (t == 'cantonese') {
      final res = PinyinConverterService.convertToCantonese(
        text,
        style: _cantoneseStyle,
        mode: _displayMode,
      );
      _outputController.text = res;
    } else {
      final res = PinyinConverterService.convertToMandarin(
        text,
        style: _mandarinStyle,
        mode: _displayMode,
      );
      _outputController.text = res;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCover = FoldUtils.isCoverScreen(context);
    final isFoldUnfolded = FoldUtils.isFoldUnfolded(context);
    final isMobile = isCover || screenWidth < 800;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(FoldUtils.getHorizontalPadding(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 頂部標題與範本選擇 (支援橫向平滑滾動，永遠不被截斷)
              _buildHeader(isMobile, isCover),
              const SizedBox(height: 10),

              // 工具列 (轉換類型、聲調風格、顯示模式、精修切換)
              _buildToolbar(isMobile, isCover),
              const SizedBox(height: 12),

              // 主體區域：手機版支援分頁與全頁面滑動；大屏/桌面支援左右雙欄
              Expanded(
                child: isMobile
                    ? _buildMobileContent(isCover)
                    : _buildWideContent(isFoldUnfolded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 頂部標題與範本 Chips (水平可滾動，保證全平台不截斷)
  Widget _buildHeader(bool isMobile, bool isCover) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isCover ? '港式廣東話 & 國語拼音' : '港式口音廣東話 & 國語拼音工作室',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isCover ? 17 : 21,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          '精準辨析 20,800+ 字符粵音 · 支援香港口音習慣 (HK Pinyin) 與國語拼音轉換',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),

        // 水平滑動的歌詞範本列
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              const Text('經典範本: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              const SizedBox(width: 6),
              ..._presets.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    label: Text(p['title']!, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                    onPressed: () {
                      _inputController.text = p['lyrics']!;
                      _doConvert();
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  /// 工具列
  Widget _buildToolbar(bool isMobile, bool isCover) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isCover ? 8 : 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.start,
        children: [
          // 港式廣東話按鈕
          ElevatedButton.icon(
            onPressed: () => _doConvert(type: 'cantonese'),
            icon: const Icon(Icons.record_voice_over, size: 14),
            label: Text(isCover ? '廣東話' : '港式廣東話拼音'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _lastConversionType == 'cantonese' ? const Color(0xFF02AF4A) : const Color(0xFF334155),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),

          // 國語拼音按鈕
          ElevatedButton.icon(
            onPressed: () => _doConvert(type: 'mandarin'),
            icon: const Icon(Icons.translate, size: 14),
            label: Text(isCover ? '國語' : '國語拼音'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _lastConversionType == 'mandarin' ? const Color(0xFF38BDF8) : const Color(0xFF334155),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),

          // 聲調風格選擇
          if (_lastConversionType == 'cantonese') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: DropdownButton<CantoneseStyle>(
                value: _cantoneseStyle,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontSize: 11),
                underline: const SizedBox(),
                isDense: true,
                items: const [
                  DropdownMenuItem(value: CantoneseStyle.hkPinyinTone, child: Text('🇭🇰 港式粵拼 (SUNO最準)')),
                  DropdownMenuItem(value: CantoneseStyle.jyutpingTone, child: Text('標準粵拼帶調')),
                  DropdownMenuItem(value: CantoneseStyle.hkPinyinNoTone, child: Text('純拼音無聲調')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _cantoneseStyle = val;
                    _doConvert();
                  }
                },
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: DropdownButton<MandarinStyle>(
                value: _mandarinStyle,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontSize: 11),
                underline: const SizedBox(),
                isDense: true,
                items: const [
                  DropdownMenuItem(value: MandarinStyle.withToneMark, child: Text('聲調符號 (hán yè)')),
                  DropdownMenuItem(value: MandarinStyle.withoutTone, child: Text('純拼音無調 (han ye)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _mandarinStyle = val;
                    _doConvert();
                  }
                },
              ),
            ),
          ],

          // 顯示模式 (純拼音 / 雙行對照 / Ruby)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: DropdownButton<PinyinDisplayMode>(
              value: _displayMode,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontSize: 11),
              underline: const SizedBox(),
              isDense: true,
              items: const [
                DropdownMenuItem(value: PinyinDisplayMode.pinyinOnly, child: Text('純拼音歌詞')),
                DropdownMenuItem(value: PinyinDisplayMode.sideBySide, child: Text('雙行對照')),
                DropdownMenuItem(value: PinyinDisplayMode.rubyStyle, child: Text('漢字(拼音)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  _displayMode = val;
                  _doConvert();
                }
              },
            ),
          ),

          // 逐字精修模式切換
          ActionChip(
            avatar: Icon(
              _viewMode == 1 ? Icons.check_circle : Icons.tune,
              size: 14,
              color: _viewMode == 1 ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
            ),
            backgroundColor: _viewMode == 1 ? const Color(0xFF02AF4A).withValues(alpha: 0.2) : const Color(0xFF0F172A),
            side: BorderSide(color: _viewMode == 1 ? const Color(0xFF02AF4A) : const Color(0xFF334155)),
            label: Text(
              _viewMode == 1 ? '逐字精修模式' : '切換逐字精修',
              style: TextStyle(
                fontSize: 11,
                color: _viewMode == 1 ? const Color(0xFF34D399) : const Color(0xFFCBD5E1),
                fontWeight: _viewMode == 1 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == 0 ? 1 : 0;
              });
            },
          ),
        ],
      ),
    );
  }

  /// 手機版介面：提供 Tab 分頁或全頁垂直滑動，確保任何內容都可順暢滑動和查看
  Widget _buildMobileContent(bool isCover) {
    return Column(
      children: [
        // 分頁切換列：[中文原詞] / [拼音結果] / [上下並列]
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 0, label: Text('中文原詞', style: TextStyle(fontSize: 12)), icon: Icon(Icons.edit, size: 14)),
              ButtonSegment<int>(value: 1, label: Text('拼音結果', style: TextStyle(fontSize: 12)), icon: Icon(Icons.spellcheck, size: 14)),
              ButtonSegment<int>(value: 2, label: Text('上下並列', style: TextStyle(fontSize: 12)), icon: Icon(Icons.splitscreen, size: 14)),
            ],
            selected: {_mobileTab},
            onSelectionChanged: (val) {
              setState(() {
                _mobileTab = val.first;
              });
            },
            style: SegmentedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              selectedBackgroundColor: const Color(0xFF02AF4A),
              selectedForegroundColor: Colors.white,
              foregroundColor: const Color(0xFF94A3B8),
            ),
          ),
        ),

        // 依據 Tab 顯示可自由滑動的內容
        Expanded(
          child: _mobileTab == 0
              ? _buildChineseInputCard(isMobile: true)
              : (_mobileTab == 1
                  ? _buildPinyinResultCard(isMobile: true)
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 280,
                            child: _buildChineseInputCard(isMobile: true),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 380,
                            child: _buildPinyinResultCard(isMobile: true),
                          ),
                        ],
                      ),
                    )),
        ),
      ],
    );
  }

  /// 寬屏 / Fold 內屏幕介面：左右雙欄完美並排
  Widget _buildWideContent(bool isFoldUnfolded) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左欄：中文歌詞輸入卡片
        Expanded(
          flex: 5,
          child: _buildChineseInputCard(isMobile: false),
        ),
        const SizedBox(width: 14),

        // 右欄：拼音結果 / 逐字精修卡片
        Expanded(
          flex: 5,
          child: _buildPinyinResultCard(isMobile: false),
        ),
      ],
    );
  }

  /// 中文歌詞輸入卡片 (完全可滾動)
  Widget _buildChineseInputCard({required bool isMobile}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.edit_note, size: 16, color: Color(0xFF38BDF8)),
                  SizedBox(width: 6),
                  Text(
                    '中文原詞 (可貼上/輸入)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Row(
                children: [
                  // 貼上剪貼簿
                  IconButton(
                    tooltip: '貼上剪貼簿內容',
                    icon: const Icon(Icons.paste, size: 15, color: Color(0xFF94A3B8)),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null && data!.text!.isNotEmpty) {
                        _inputController.text = data.text!;
                        _doConvert();
                      }
                    },
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _inputController.clear();
                      _outputController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear, size: 14, color: Color(0xFFF87171)),
                    label: const Text('清空', style: TextStyle(color: Color(0xFFF87171), fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 16),
          // 輸入區域 (支援自由滑動)
          Expanded(
            child: TextField(
              controller: _inputController,
              maxLines: null,
              expands: true,
              scrollPhysics: const AlwaysScrollableScrollPhysics(),
              onChanged: (_) => _doConvert(),
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.6),
              decoration: const InputDecoration(
                hintText: '喺度輸入或貼上中文字歌詞，右邊/下方會即時轉換拼音...',
                hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 拼音結果卡片 (支援文字滾動或逐字精修)
  Widget _buildPinyinResultCard({required bool isMobile}) {
    final isCantonese = _lastConversionType == 'cantonese';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCantonese ? const Color(0xFF02AF4A).withValues(alpha: 0.3) : const Color(0xFF38BDF8).withValues(alpha: 0.3),
        ),
      ),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isCantonese ? '🇭🇰 廣東話拼音結果' : '🇨🇳 國語拼音結果',
                  style: TextStyle(
                    color: isCantonese ? const Color(0xFF02AF4A) : const Color(0xFF38BDF8),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 複製按鈕
                  IconButton(
                    tooltip: '複製轉換結果',
                    icon: const Icon(Icons.copy, size: 16, color: Color(0xFFCBD5E1)),
                    onPressed: () {
                      if (_outputController.text.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: _outputController.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✓ 拼音歌詞已複製到剪貼簿！')),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 4),

                  // 套用至上傳按鈕
                  ElevatedButton.icon(
                    onPressed: () {
                      final txt = _outputController.text.trim();
                      if (txt.isNotEmpty) {
                        widget.onApplyToUpload?.call(txt);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✓ 已成功將此拼音歌詞套用到上傳視窗！')),
                        );
                      }
                    },
                    icon: const Icon(Icons.upload_file, size: 13),
                    label: const Text('套用到上傳'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF02AF4A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 16),

          // 主內容區：逐字精修或純文字展示 (皆支援極致流暢滑動)
          Expanded(
            child: _viewMode == 1
                ? SideBySideLyricEditor(
                    rawLyrics: _inputController.text,
                    cantoneseStyle: _cantoneseStyle,
                    onPinyinLyricsChanged: (updated) {
                      _outputController.text = updated;
                      setState(() {});
                    },
                  )
                : TextField(
                    controller: _outputController,
                    maxLines: null,
                    expands: true,
                    scrollPhysics: const AlwaysScrollableScrollPhysics(),
                    style: const TextStyle(
                      color: Color(0xFFF1F5F9),
                      fontSize: 13,
                      height: 1.6,
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      hintText: '拼音轉換結果會即時顯示喺呢度...',
                      hintStyle: TextStyle(color: Color(0xFF64748B)),
                      border: InputBorder.none,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
