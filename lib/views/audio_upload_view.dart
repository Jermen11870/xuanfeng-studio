import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/fold_utils.dart';
import '../services/audio_player_service.dart';
import '../widgets/interactive_lyric_grid.dart';
import '../services/pinyin_converter_service.dart';
import '../services/youtube_audio_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/audio_track.dart';
import '../models/upload_task.dart';
import '../services/audio_track_service.dart';
import '../services/suno_token_service.dart';
import '../services/suno_upload_service.dart';
import '../widgets/waveform_track_widget.dart';
import 'suno_mobile_login_screen.dart';
import '../widgets/suno_web_login_dialog.dart';

class AudioUploadView extends StatefulWidget {
  const AudioUploadView({super.key});

  @override
  State<AudioUploadView> createState() => _AudioUploadViewState();
}

class _AudioUploadViewState extends State<AudioUploadView> {
  int _lyricsDisplayTab = 0;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _styleController = TextEditingController();
  final TextEditingController _youtubeUrlController = TextEditingController();
  final HighlightTextEditingController _chineseLyricsController = HighlightTextEditingController(
    highlightColor: const Color(0xFF10B981),
  );
  final HighlightTextEditingController _pinyinLyricsController = HighlightTextEditingController(
    highlightColor: const Color(0xFF38BDF8),
  );
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    PinyinConverterService.init();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _styleController.dispose();
    _youtubeUrlController.dispose();
    _chineseLyricsController.dispose();
    _pinyinLyricsController.dispose();
    super.dispose();
  }

  /// 供外部或歌詞工作室設定歌詞
  void setLyrics(String lyrics) {
    _chineseLyricsController.text = lyrics;
    _pinyinLyricsController.text = PinyinConverterService.convertToCantonese(lyrics, style: CantoneseStyle.hkPinyinTone);
    setState(() {});
  }

  void _syncControllers(AudioTrack? track) {
    if (track != null && _titleController.text.isEmpty) {
      _titleController.text = track.title;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackService = context.watch<AudioTrackService>();
    final uploadService = context.watch<SunoUploadService>();
    final tokenService = context.watch<SunoTokenService>();

    final track = trackService.currentTrack;
    final task = uploadService.currentTask;
    final isUploading = uploadService.isUploading;
    final isLoggedIn = tokenService.isLoggedIn;
    final history = uploadService.historyTasks;

    final isCover = FoldUtils.isCoverScreen(context);
    final isFoldUnfolded = FoldUtils.isFoldUnfolded(context);
    final isWide = FoldUtils.isWideOrExpanded(context);
    final useTwoColumns = (isFoldUnfolded || isWide) && MediaQuery.of(context).size.width >= 620;

    _syncControllers(track);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '音軌載入與 Suno 雲端上傳',
                style: TextStyle(
                  fontSize: isCover ? 18 : 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            if (isFoldUnfolded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF02AF4A).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF02AF4A)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dashboard_customize, size: 13, color: Color(0xFF34D399)),
                    SizedBox(width: 4),
                    Text('Z Fold 7 雙欄模式', style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '支援直接拖曳或點選載入本地音檔（MP3, WAV, FLAC, M4A）。內建 4X 變速防審查技術，點擊音軌即可播放試聽，上傳完成後可直接打開 Suno 官方歌曲。',
          style: TextStyle(fontSize: isCover ? 12 : 13, color: const Color(0xFF94A3B8)),
        ),
        SizedBox(height: isCover ? 14 : 20),

        // ★ 核心工作區：若為 Samsung Z Fold 7 展開大屏 (useTwoColumns)，採用極致雙欄佈局 ★
        if (useTwoColumns) ...[
          if (track == null) ...[
            // 尚未選擇音訊時：左邊拖曳選擇，右邊 YouTube 貼上解析
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _buildDropZone(context, trackService)),
                const SizedBox(width: 18),
                Expanded(flex: 5, child: _buildYoutubeInputCard(context)),
              ],
            ),
          ] else ...[
            // 已選擇音訊時：左欄（波形、播放器、Console），右欄（模式選擇、歌詞、上傳按鈕）
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 48,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WaveformTrackWidget(
                        track: track,
                        onClear: () {
                          trackService.clearTrack();
                          _titleController.clear();
                          _styleController.clear();
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildYoutubeInputCard(context),
                      if (task != null) ...[
                        const SizedBox(height: 16),
                        _buildUploadConsoleCard(context, task, uploadService),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 52,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildModeSelector(context, uploadService, isUploading),
                      const SizedBox(height: 16),
                      _buildMetadataCard(context, trackService, isUploading),
                      const SizedBox(height: 16),
                      _buildActionButtons(context, uploadService, track, isLoggedIn, isUploading),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ] else ...[
          // ★ 外前屏或一般窄屏：流暢緊湊單欄佈局 ★
          if (track == null) ...[
            _buildDropZone(context, trackService),
            SizedBox(height: isCover ? 12 : 18),
            _buildYoutubeInputCard(context),
          ] else ...[
            WaveformTrackWidget(
              track: track,
              onClear: () {
                trackService.clearTrack();
                _titleController.clear();
                _styleController.clear();
              },
            ),
            SizedBox(height: isCover ? 12 : 18),
            _buildModeSelector(context, uploadService, isUploading),
            SizedBox(height: isCover ? 12 : 18),
            _buildMetadataCard(context, trackService, isUploading),
            SizedBox(height: isCover ? 12 : 18),
            _buildActionButtons(context, uploadService, track, isLoggedIn, isUploading),
          ],

          if (task != null) ...[
            SizedBox(height: isCover ? 16 : 24),
            _buildUploadConsoleCard(context, task, uploadService),
          ],
        ],

        // 顯示解析或載入錯誤
        if (trackService.errorMessage != null) ...[
          const SizedBox(height: 14),
          _buildErrorBanner(trackService.errorMessage!),
        ],

        // 歷史上傳歌曲列表
        if (history.isNotEmpty && !useTwoColumns) ...[
          const SizedBox(height: 28),
          _buildHistorySection(context, history, uploadService),
        ] else if (history.isNotEmpty && useTwoColumns) ...[
          const SizedBox(height: 32),
          _buildHistorySection(context, history, uploadService),
        ],
      ],
    );
  }

  Widget _buildModeSelector(BuildContext context, SunoUploadService uploadService, bool isUploading) {
    final isBypass = uploadService.mode == UploadMode.bypassWarp;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBypass ? const Color(0xFF059669) : const Color(0xFF334155),
          width: 1.5,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: isBypass ? const Color(0xFF34D399) : Colors.white70,
                  size: 22,
                ),
              const SizedBox(width: 10),
              const Text(
                '防審查與上傳模式',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isBypass
                      ? const Color(0xFF065F46).withValues(alpha: 0.6)
                      : const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isBypass ? '★ 100% 避開指紋審查' : '標準直傳',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isBypass ? const Color(0xFF34D399) : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ignore: deprecated_member_use
          RadioListTile<UploadMode>(
            value: UploadMode.bypassWarp,
            // ignore: deprecated_member_use
            groupValue: uploadService.mode,
            // ignore: deprecated_member_use
            onChanged: isUploading ? null : (val) => uploadService.setMode(val!),
            activeColor: const Color(0xFF34D399),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '4X 變速防審查模式 (推薦 · 徹底避開 Existing Recording 攔截)',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            subtitle: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '本地 4X 變速重構頻譜包絡 + 10 秒定長切片分段上傳，再由 Suno Studio Warp 雲端精確還原 100% 原速與原音質。',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ),
          ),
          // ignore: deprecated_member_use
          RadioListTile<UploadMode>(
            value: UploadMode.direct,
            // ignore: deprecated_member_use
            groupValue: uploadService.mode,
            // ignore: deprecated_member_use
            onChanged: isUploading ? null : (val) => uploadService.setMode(val!),
            activeColor: Colors.cyanAccent,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '快速原樣直傳模式 (僅適用於原創短音訊)',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            subtitle: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '直接上傳原始檔案。若歌曲被 Audible Magic 比對到版權錄音庫，將會直接被拒絕。',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ),
          ),
          if (kIsWeb)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF34D399), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚡ Web 端已就緒：採用瀏覽器原生 Web Audio API 離線 4X 變速切片引擎，同樣具備 100% 避開版權審查能力！',
                      style: TextStyle(color: Color(0xFF34D399), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildDropZone(BuildContext context, AudioTrackService service) {
    final isMobile = MediaQuery.of(context).size.width < 650;

    return DropTarget(
      onDragEntered: (detail) => setState(() => _isDragging = true),
      onDragExited: (detail) => setState(() => _isDragging = false),
      onDragDone: (detail) async {
        setState(() => _isDragging = false);
        if (detail.files.isNotEmpty) {
          final droppedFile = detail.files.first;
          if (kIsWeb) {
            final bytes = await droppedFile.readAsBytes();
            await service.loadAudioFileFromBytes(droppedFile.name, bytes);
          } else {
            await service.loadAudioFileFromPath(droppedFile.path);
          }
        }
      },
      child: InkWell(
        onTap: service.isProcessing ? null : () => service.pickAudioFile(),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: isMobile ? 135 : 185,
          width: double.infinity,
          decoration: BoxDecoration(
            color: _isDragging
                ? Colors.cyanAccent.withValues(alpha: 0.12)
                : const Color(0xFF1E293B).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isDragging
                  ? Colors.cyanAccent
                  : const Color(0xFF3B82F6).withValues(alpha: 0.5),
              width: _isDragging ? 2.5 : 1.5,
            ),
          ),
          child: Center(
            child: service.isProcessing
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.cyanAccent),
                      SizedBox(height: 14),
                      Text('正在解析音軌長度與波形特徵...', style: TextStyle(color: Colors.white70)),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isDragging ? Icons.file_download : Icons.cloud_upload_outlined,
                        size: isMobile ? 38 : 50,
                        color: _isDragging ? Colors.cyanAccent : const Color(0xFF60A5FA),
                      ),
                      SizedBox(height: isMobile ? 8 : 12),
                      Text(
                        isMobile
                            ? '點擊此處選取手機音訊檔案'
                            : (_isDragging ? '鬆開滑鼠即可立即載入音檔' : '拖曳音訊檔案至此，或點擊此處選取'),
                        style: TextStyle(
                          fontSize: isMobile ? 15 : 16,
                          fontWeight: FontWeight.bold,
                          color: _isDragging ? Colors.cyanAccent : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isMobile
                            ? '支援 MP3, WAV, FLAC, M4A, AAC 等格式'
                            : '支援從 Finder 直接拖入 MP3, WAV, FLAC, M4A, AAC 等格式',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildYoutubeInputCard(BuildContext context) {
    final ytService = context.watch<YoutubeAudioService>();
    final isProcessing = ytService.isDownloading || ytService.isLoadingInfo;
    final info = ytService.currentVideoInfo;
    final isMobile = MediaQuery.of(context).size.width < 650;

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.smart_display, color: Color(0xFFEF4444), size: 18),
              ),
              const SizedBox(width: 8),
              const Text(
                'YouTube 連結快速匯入',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, color: Color(0xFFFCA5A5), size: 13),
                    SizedBox(width: 3),
                    Text(
                      '免裝工具',
                      style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '貼上 YouTube 影片網址，自動獲取縮圖、標題與影片資訊，並提取最高音質音訊直傳 Suno！',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 14),

          // 網址輸入與解析區 (響應式手機排版)
          if (isMobile) ...[
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const Icon(Icons.link, color: Color(0xFF64748B), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _youtubeUrlController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      enabled: !isProcessing,
                      decoration: const InputDecoration(
                        hintText: '貼上 YouTube 網址...',
                        hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (val) => _onYoutubeUrlChanged(context, val),
                      onSubmitted: (val) => _onYoutubeUrlChanged(context, val),
                    ),
                  ),
                  if (_youtubeUrlController.text.isNotEmpty && !isProcessing)
                    IconButton(
                      icon: const Icon(Icons.clear, color: Color(0xFF64748B), size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _youtubeUrlController.clear();
                        ytService.reset();
                        setState(() {});
                      },
                    ),
                  const SizedBox(width: 6),
                  // 內建貼上小圖標
                  InkWell(
                    onTap: isProcessing
                        ? null
                        : () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null && data!.text!.trim().isNotEmpty) {
                              _youtubeUrlController.text = data.text!.trim();
                              setState(() {});
                              if (context.mounted) {
                                _onYoutubeUrlChanged(context, _youtubeUrlController.text);
                              }
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.content_paste, size: 13, color: Color(0xFFCBD5E1)),
                          SizedBox(width: 3),
                          Text('貼上', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: isProcessing
                    ? null
                    : () => _onYoutubeUrlChanged(context, _youtubeUrlController.text),
                icon: ytService.isLoadingInfo
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search, size: 15),
                label: Text(ytService.isLoadingInfo ? '正在獲取影片資訊...' : '立即解析 YouTube 影片'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.link, color: Color(0xFF64748B), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _youtubeUrlController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            enabled: !isProcessing,
                            decoration: const InputDecoration(
                              hintText: '貼上 YouTube 網址 (如 https://www.youtube.com/watch?v=... 或 https://youtu.be/...)',
                              hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (val) => _onYoutubeUrlChanged(context, val),
                            onSubmitted: (val) => _onYoutubeUrlChanged(context, val),
                          ),
                        ),
                        if (_youtubeUrlController.text.isNotEmpty && !isProcessing)
                          IconButton(
                            icon: const Icon(Icons.clear, color: Color(0xFF64748B), size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              _youtubeUrlController.clear();
                              ytService.reset();
                              setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 貼上剪貼簿按鈕
                OutlinedButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null && data!.text!.trim().isNotEmpty) {
                            _youtubeUrlController.text = data.text!.trim();
                            setState(() {});
                            if (context.mounted) {
                              _onYoutubeUrlChanged(context, _youtubeUrlController.text);
                            }
                          }
                        },
                  icon: const Icon(Icons.content_paste, size: 15),
                  label: const Text('貼上'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF94A3B8),
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 10),
                // 手動解析/刷新按鈕
                ElevatedButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () => _onYoutubeUrlChanged(context, _youtubeUrlController.text),
                  icon: ytService.isLoadingInfo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.search, size: 16),
                  label: Text(ytService.isLoadingInfo ? '解析中...' : '解析影片'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],

          // 載入資訊中的提示
          if (ytService.isLoadingInfo) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)),
                  ),
                  SizedBox(width: 10),
                  Text(
                    '正在獲取 YouTube 高清縮圖與影片資訊...',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],

          // 影片縮圖與詳細資訊預覽卡片
          if (info != null && !ytService.isLoadingInfo) ...[
            const SizedBox(height: 14),
            Container(
              padding: EdgeInsets.all(isMobile ? 12 : 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isMobile)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 手機版：全寬比例縮圖
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: double.infinity,
                                  color: const Color(0xFF1E293B),
                                  child: info.thumbnailUrl.isNotEmpty
                                      ? Image.network(
                                          info.thumbnailUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Center(
                                            child: Icon(Icons.broken_image, color: Colors.white24, size: 32),
                                          ),
                                        )
                                      : const Center(
                                          child: Icon(Icons.music_video, color: Colors.white24, size: 32),
                                        ),
                                ),
                                // 播放按鈕浮層
                                InkWell(
                                  onTap: () => ytService.playInApp(info),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.7),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
                                    ),
                                    child: const Icon(Icons.play_arrow, color: Color(0xFFEF4444), size: 26),
                                  ),
                                ),
                                // 右下角時長
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      info.formattedDuration,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // 標題與作者
                        Text(
                          info.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.account_circle, color: Color(0xFF94A3B8), size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                info.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              ),
                            ),
                            if (info.formattedViews.isNotEmpty) ...[
                              Text(
                                info.formattedViews,
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        // 操作按鈕區 (Wrap)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => ytService.playInApp(info),
                              icon: const Icon(Icons.play_circle_outline, size: 14, color: Color(0xFF38BDF8)),
                              label: const Text('播放', style: TextStyle(fontSize: 11, color: Color(0xFF38BDF8))),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF0284C7)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => ytService.openInExternal(info),
                              icon: const Icon(Icons.open_in_new, size: 13, color: Color(0xFFFCA5A5)),
                              label: const Text('YouTube 開啟', style: TextStyle(fontSize: 11, color: Color(0xFFFCA5A5))),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFEF4444)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: isProcessing ? null : () => _handleYoutubeDownload(context),
                              icon: ytService.isDownloading
                                  ? const SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.cloud_download, size: 14),
                              label: Text(ytService.isDownloading
                                  ? '下載中 (${ytService.percentage}%)...'
                                  : '⚡ 下載音訊並準備上傳'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF02AF4A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左側：16:9 高清縮圖（點擊在 APP 內直接播放）
                        Tooltip(
                          message: '點擊在 APP 內直接播放',
                          child: InkWell(
                            onTap: () => ytService.playInApp(info),
                            borderRadius: BorderRadius.circular(8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 160,
                                    height: 90,
                                    color: const Color(0xFF1E293B),
                                    child: info.thumbnailUrl.isNotEmpty
                                        ? Image.network(
                                            info.thumbnailUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) => const Center(
                                              child: Icon(Icons.broken_image, color: Colors.white24, size: 32),
                                            ),
                                          )
                                        : const Center(
                                            child: Icon(Icons.music_video, color: Colors.white24, size: 32),
                                          ),
                                  ),
                                  // 播放按鈕浮層
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.7),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
                                    ),
                                    child: const Icon(Icons.play_arrow, color: Color(0xFFEF4444), size: 22),
                                  ),
                                  // 右下角時長 Badge
                                  Positioned(
                                    right: 6,
                                    bottom: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.85),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        info.formattedDuration,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // 右側：影片標題、頻道名稱、觀看統計與標籤
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                info.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.account_circle, color: Color(0xFF94A3B8), size: 14),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      info.author,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                    ),
                                  ),
                                  if (info.formattedViews.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      info.formattedViews,
                                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  // 在 APP 內播放按鈕
                                  OutlinedButton.icon(
                                    onPressed: () => ytService.playInApp(info),
                                    icon: const Icon(Icons.play_circle_outline, size: 15, color: Color(0xFF38BDF8)),
                                    label: const Text('在 APP 內播放', style: TextStyle(fontSize: 12, color: Color(0xFF38BDF8))),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFF0284C7)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                  // 在 YouTube 開啟按鈕
                                  OutlinedButton.icon(
                                    onPressed: () => ytService.openInExternal(info),
                                    icon: const Icon(Icons.open_in_new, size: 14, color: Color(0xFFFCA5A5)),
                                    label: const Text('在 YouTube 開啟', style: TextStyle(fontSize: 12, color: Color(0xFFFCA5A5))),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFFEF4444)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                  // 下載並載入按鈕
                                  ElevatedButton.icon(
                                    onPressed: isProcessing ? null : () => _handleYoutubeDownload(context),
                                    icon: ytService.isDownloading
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.cloud_download, size: 15),
                                    label: Text(ytService.isDownloading
                                        ? '正在下載 (${ytService.percentage}%)...'
                                        : '⚡ 下載音訊並準備上傳'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF02AF4A),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                  // 下載進度條 (帶清晰高亮 % 顯示)
                  if (ytService.isDownloading) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF02AF4A).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF02AF4A)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    ytService.statusMessage,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  if (ytService.formattedSizeProgress.isNotEmpty) ...[
                                    Text(
                                      ytService.formattedSizeProgress,
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF02AF4A).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF02AF4A)),
                                    ),
                                    child: Text(
                                      '${ytService.percentage}%',
                                      style: const TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ytService.downloadProgress > 0 ? ytService.downloadProgress : null,
                              backgroundColor: const Color(0xFF334155),
                              color: const Color(0xFF02AF4A),
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // 錯誤提示
          if (ytService.errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ytService.errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _onYoutubeUrlChanged(BuildContext context, String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final ytService = context.read<YoutubeAudioService>();
    if (ytService.isValidYoutubeUrl(trimmed)) {
      ytService.fetchVideoInfo(trimmed).then((info) {
        if (info != null && mounted) {
          // 影片資訊獲取後自動啟動高速下載
          _handleYoutubeDownload(this.context);
        }
      });
    }
  }

  Future<void> _handleYoutubeDownload(BuildContext context) async {
    final url = _youtubeUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先輸入或貼上 YouTube 網址')),
      );
      return;
    }
    final ytService = context.read<YoutubeAudioService>();
    final track = await ytService.downloadAndLoadAudio(url);
    if (track != null) {
      _titleController.text = track.title;
      setState(() {});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF02AF4A),
            content: Text('已成功載入 YouTube 音訊：「${track.title}」，可以直接上傳至 Suno！'),
          ),
        );
      }
    }
  }

  Widget _buildMetadataCard(BuildContext context, AudioTrackService service, bool isUploading) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suno 作品資訊設定 (可選)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _titleController,
                  enabled: !isUploading,
                  onChanged: (val) => service.updateMetadata(title: val),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: '曲目標題 (Title)',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: Icon(Icons.title, color: Colors.cyanAccent, size: 20),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _styleController,
                  enabled: !isUploading,
                  onChanged: (val) => service.updateMetadata(style: val),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: '風格標籤 (Style/Tags)',
                    hintText: '如: Pop, Acoustic',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: Icon(Icons.label_outline, color: Colors.cyanAccent, size: 20),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DualLyricEditor(
            chineseController: _chineseLyricsController,
            pinyinController: _pinyinLyricsController,
            enabled: !isUploading,
            onChanged: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    SunoUploadService uploadService,
    AudioTrack track,
    bool isLoggedIn,
    bool isUploading,
  ) {
    final isBypass = uploadService.mode == UploadMode.bypassWarp;
    final isMobile = MediaQuery.of(context).size.width < 650;

    final uploadBtn = ElevatedButton.icon(
      onPressed: (!isLoggedIn || isUploading)
          ? null
          : () {
              uploadService.startUpload(track, customTitle: _titleController.text, lyrics: _pinyinLyricsController.text.trim().isNotEmpty ? _pinyinLyricsController.text.trim() : _chineseLyricsController.text.trim());
            },
      icon: isUploading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : Icon(isBypass ? Icons.verified : Icons.cloud_upload, size: 20),
      label: Text(
        isUploading
            ? '上傳與雲端還原中...'
            : (!isLoggedIn
                ? '請先連接 Suno 帳號'
                : (isBypass ? '啟動 4X 防審查上傳至 Suno' : '開始直傳至 Suno 作品庫')),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isBypass ? const Color(0xFF059669) : const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF334155),
        disabledForegroundColor: Colors.white38,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    final reuploadBtn = ElevatedButton.icon(
      onPressed: (!isLoggedIn)
          ? null
          : () {
              final lyrics = _pinyinLyricsController.text.trim().isNotEmpty
                  ? _pinyinLyricsController.text.trim()
                  : _chineseLyricsController.text.trim();
              uploadService.startUpload(
                track,
                customTitle: _titleController.text,
                lyrics: lyrics,
              );
            },
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('重新上傳'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD97706),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    final cancelBtn = OutlinedButton(
      onPressed: () => uploadService.cancelUpload(),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.redAccent,
        side: const BorderSide(color: Colors.redAccent),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      child: const Text('取消任務'),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          uploadBtn,
          if (!isUploading) ...[
            const SizedBox(height: 10),
            reuploadBtn,
          ],
          if (isUploading) ...[
            const SizedBox(height: 10),
            cancelBtn,
          ],
        ],
      );
    }

    return Row(
      children: [
        uploadBtn,
        if (!isUploading) ...[
          const SizedBox(width: 14),
          reuploadBtn,
        ],
        if (isUploading) ...[
          const SizedBox(width: 12),
          cancelBtn,
        ],
      ],
    );
  }

  Widget _buildUploadConsoleCard(
    BuildContext context,
    UploadTask task,
    SunoUploadService uploadService,
  ) {
    final isSuccess = task.isSuccess;
    final isFailed = task.isFailed;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSuccess
              ? const Color(0xFF10B981)
              : isFailed
                  ? Colors.redAccent
                  : const Color(0xFF3B82F6),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 狀態與百分比
          Row(
            children: [
              Icon(
                isSuccess
                    ? Icons.check_circle
                    : isFailed
                        ? Icons.error_outline
                        : Icons.sync,
                color: isSuccess
                    ? const Color(0xFF10B981)
                    : isFailed
                        ? Colors.redAccent
                        : Colors.cyanAccent,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.statusMessage,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              Text(
                '${(task.progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isSuccess
                      ? const Color(0xFF10B981)
                      : isFailed
                          ? Colors.redAccent
                          : Colors.cyanAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 高精度進度條
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: task.progress,
              backgroundColor: const Color(0xFF0F172A),
              color: isSuccess
                  ? const Color(0xFF10B981)
                  : isFailed
                      ? Colors.redAccent
                      : Colors.cyanAccent,
              minHeight: 10,
            ),
          ),
          if (isFailed) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                      SunoMobileLoginScreen.show(context);
                    } else {
                      SunoWebLoginDialog.show(context);
                    }
                  },
                  icon: Icon(
                    (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ? Icons.login : Icons.language,
                    size: 16,
                  ),
                  label: Text((!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ? '一鍵登入 Suno' : '登入 Suno (取得 Token)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final lyrics = _pinyinLyricsController.text.trim().isNotEmpty
                        ? _pinyinLyricsController.text.trim()
                        : _chineseLyricsController.text.trim();
                    final track = context.read<AudioTrackService>().currentTrack;
                    if (track != null) {
                      uploadService.startUpload(track, customTitle: _titleController.text, lyrics: lyrics);
                    }
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重新上傳 (重試)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),

          // ★ 上傳成功：顯示直接打開歌曲按鈕與專屬連結 ★
          if (isSuccess && task.clipId != null) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF065F46).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF059669), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isMobile)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle_outline, color: Color(0xFF34D399), size: 22),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Suno 官方入庫成功！歌曲已生成',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // 播放/試聽音檔按鈕
                            OutlinedButton.icon(
                              onPressed: () async {
                                final player = context.read<AudioPlayerService>();
                                final track = context.read<AudioTrackService>().currentTrack;
                                try {
                                  if (track != null) {
                                    await player.playTrack(track);
                                  } else {
                                    await player.playCustom(
                                      id: task.clipId!,
                                      title: _titleController.text.isNotEmpty ? _titleController.text : 'Suno 成曲',
                                      url: 'https://cdn1.suno.ai/${task.clipId}.mp3',
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('播放失敗：$e'), backgroundColor: const Color(0xFFEF4444)),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.play_circle_fill, size: 15, color: Color(0xFF34D399)),
                              label: const Text('播放音檔', style: TextStyle(fontSize: 12, color: Color(0xFF34D399), fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF34D399)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                final lyrics = _pinyinLyricsController.text.trim().isNotEmpty
                                    ? _pinyinLyricsController.text.trim()
                                    : _chineseLyricsController.text.trim();
                                final track = context.read<AudioTrackService>().currentTrack;
                                if (track != null) {
                                  uploadService.startUpload(track, customTitle: _titleController.text, lyrics: lyrics);
                                }
                              },
                              icon: const Icon(Icons.refresh, size: 15),
                              label: const Text('重新上傳', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFBBF24),
                                side: const BorderSide(color: Color(0xFFFBBF24)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => uploadService.openSongInBrowser(task.clipId!),
                              icon: const Icon(Icons.open_in_new, size: 15),
                              label: const Text('打開 Suno 歌曲', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: Color(0xFF34D399), size: 26),
                        const SizedBox(width: 10),
                        const Text(
                          'Suno 官方入庫成功！歌曲已生成',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final player = context.read<AudioPlayerService>();
                            final track = context.read<AudioTrackService>().currentTrack;
                            try {
                              if (track != null) {
                                await player.playTrack(track);
                              } else {
                                await player.playCustom(
                                  id: task.clipId!,
                                  title: _titleController.text.isNotEmpty ? _titleController.text : 'Suno 成曲',
                                  url: 'https://cdn1.suno.ai/${task.clipId}.mp3',
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('播放失敗：$e'), backgroundColor: const Color(0xFFEF4444)),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.play_circle_fill, size: 16, color: Color(0xFF34D399)),
                          label: const Text('播放音檔', style: TextStyle(fontSize: 13, color: Color(0xFF34D399), fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF34D399)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            final lyrics = _pinyinLyricsController.text.trim().isNotEmpty
                                ? _pinyinLyricsController.text.trim()
                                : _chineseLyricsController.text.trim();
                            final track = context.read<AudioTrackService>().currentTrack;
                            if (track != null) {
                              uploadService.startUpload(track, customTitle: _titleController.text, lyrics: lyrics);
                            }
                          },
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('重新上傳'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFBBF24),
                            side: const BorderSide(color: Color(0xFFFBBF24)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => uploadService.openSongInBrowser(task.clipId!),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('打開 Suno 歌曲'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  const Divider(color: Color(0xFF047857), height: 24),

                  // 連結預覽與複製 (響應式分流)
                  if (isMobile)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Suno 歌曲連結：', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        const SizedBox(height: 6),
                        SelectableText(
                          'https://suno.com/song/${task.clipId}',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await uploadService.copySongUrl(task.clipId!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已複製 Suno 歌曲連結至剪貼簿！'),
                                  backgroundColor: Color(0xFF059669),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('複製歌曲連結'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF059669)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        const Text('Suno 歌曲連結：', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        Expanded(
                          child: SelectableText(
                            'https://suno.com/song/${task.clipId}',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await uploadService.copySongUrl(task.clipId!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已複製 Suno 歌曲連結至剪貼簿！'),
                                  backgroundColor: Color(0xFF059669),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('複製連結'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF059669)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                      ],
                    ),

                  // 同分頁顯示已上傳歌詞與拼音區塊
                  const SizedBox(height: 18),
                  _buildUploadedLyricsSection(context, task, uploadService),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // 實時日誌終端
          const Text(
            '即時執行日誌 (Live Console Log)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 8),
          Container(
            height: 140,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: ListView.builder(
              reverse: true,
              itemCount: task.logs.length,
              itemBuilder: (ctx, i) {
                final logIndex = task.logs.length - 1 - i;
                final line = task.logs[logIndex];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 12,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  
  Widget _buildUploadedLyricsSection(BuildContext context, UploadTask task, SunoUploadService uploadService) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final lyrics = task.lyrics.trim();
    final hasLyrics = lyrics.isNotEmpty;
    final cantonese = task.cantoneseLyrics.isNotEmpty
        ? task.cantoneseLyrics
        : (hasLyrics ? PinyinConverterService.convertToCantonese(lyrics, style: CantoneseStyle.hkPinyinTone) : '');
    final mandarin = task.mandarinLyrics.isNotEmpty
        ? task.mandarinLyrics
        : (hasLyrics ? PinyinConverterService.convertToMandarin(lyrics, style: MandarinStyle.withToneMark) : '');

    String currentDisplayText = '';
    if (_lyricsDisplayTab == 0) {
      currentDisplayText = hasLyrics ? lyrics : '(此歌曲上傳時未填寫歌詞，可點擊右側按鈕補填)';
    } else if (_lyricsDisplayTab == 1) {
      currentDisplayText = cantonese.isNotEmpty ? cantonese : '(暫無廣東話拼音)';
    } else {
      currentDisplayText = mandarin.isNotEmpty ? mandarin : '(暫無國語拼音)';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Row(
              children: [
                const Icon(Icons.lyrics, color: Color(0xFF34D399), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已上傳歌詞 · 《${task.title.isNotEmpty ? task.title : task.fileName}》',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLyricsTabButton('中文原詞', 0),
                      _buildLyricsTabButton('🇭🇰 港式粵拼', 1),
                      _buildLyricsTabButton('🇨🇳 國語拼音', 2),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showQuickEditLyricsDialog(context, task, uploadService),
                  icon: const Icon(Icons.edit_note, size: 15),
                  label: const Text('修改歌名/歌詞', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF34D399),
                    side: const BorderSide(color: Color(0xFF059669)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.lyrics, color: Color(0xFF34D399), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已上傳歌曲歌詞 · 《${task.title.isNotEmpty ? task.title : task.fileName}》',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      _buildLyricsTabButton('中文原詞', 0),
                      _buildLyricsTabButton('🇭🇰 港式粵拼', 1),
                      _buildLyricsTabButton('🇨🇳 國語拼音', 2),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _showQuickEditLyricsDialog(context, task, uploadService),
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text('修改歌名/歌詞'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF34D399),
                    side: const BorderSide(color: Color(0xFF059669)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              currentDisplayText,
              style: TextStyle(
                color: hasLyrics ? const Color(0xFFF1F5F9) : const Color(0xFF64748B),
                fontSize: 13,
                height: 1.6,
                fontFamily: _lyricsDisplayTab > 0 ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsTabButton(String label, int index) {
    final isSelected = _lyricsDisplayTab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _lyricsDisplayTab = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF02AF4A) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _showQuickEditLyricsDialog(BuildContext context, UploadTask task, SunoUploadService uploadService) {
    final titleCtrl = TextEditingController(text: task.title);
    final lyricsCtrl = TextEditingController(text: task.lyrics);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.edit, color: Color(0xFF02AF4A), size: 20),
              SizedBox(width: 8),
              Text('即時修改歌名與歌詞 (同步 Suno)', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('曲目標題', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('歌詞內容 (Prompt / Lyrics)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              final raw = lyricsCtrl.text;
                              if (raw.isNotEmpty) {
                                lyricsCtrl.text = PinyinConverterService.convertToCantonese(raw, style: CantoneseStyle.hkPinyinTone);
                              }
                            },
                            child: const Text('轉廣東話帶音調', style: TextStyle(color: Color(0xFF02AF4A), fontSize: 11)),
                          ),
                          TextButton(
                            onPressed: () {
                              final raw = lyricsCtrl.text;
                              if (raw.isNotEmpty) {
                                lyricsCtrl.text = PinyinConverterService.convertToMandarin(raw, style: MandarinStyle.withToneMark);
                              }
                            },
                            child: const Text('轉國語拼音', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: lyricsCtrl,
                    maxLines: 8,
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
                    decoration: InputDecoration(
                      hintText: '輸入或貼上歌詞...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B)),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              onPressed: () async {
                final newTitle = titleCtrl.text.trim();
                final newLyrics = lyricsCtrl.text.trim();
                await uploadService.updateCurrentTaskInfo(
                  newTitle: newTitle.isEmpty ? task.title : newTitle,
                  newLyrics: newLyrics,
                );
                setState(() {});
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✓ 歌名與歌詞已即時更新並同步至 Suno 雲端！')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF02AF4A),
                foregroundColor: Colors.white,
              ),
              child: const Text('同步更新至 Suno'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistorySection(
    BuildContext context,
    List<UploadTask> history,
    SunoUploadService uploadService,
  ) {
    final completedItems = history.where((t) => t.isSuccess && t.clipId != null).toList();
    if (completedItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '已上傳歌曲歷史',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        ...completedItems.map((task) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                const Icon(Icons.music_note, color: Colors.cyanAccent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Clip ID: ${task.clipId} · ${task.createdAt.toLocal().toString().split('.')[0]}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => uploadService.openSongInBrowser(task.clipId!),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打開歌曲'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
