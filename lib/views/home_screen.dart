import 'dart:io';
import 'package:flutter/foundation.dart';
import '../widgets/clean_slices_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/suno_token.dart';
import '../services/suno_auth_service.dart';
import '../services/suno_token_service.dart';
import 'audio_upload_view.dart';
import 'lyrics_pinyin_view.dart';
import 'suno_mobile_login_screen.dart';
import 'upload_history_view.dart';
import '../services/upload_history_service.dart';
import '../widgets/suno_web_login_dialog.dart';

import '../core/fold_utils.dart';
import '../widgets/mini_audio_player_bar.dart';

class HomeScreen extends StatefulWidget {
  final SunoAuthService authService;

  const HomeScreen({super.key, required this.authService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<State<AudioUploadView>> _uploadViewKey = GlobalKey<State<AudioUploadView>>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 2 && !_tabController.indexIsChanging) {
        context.read<UploadHistoryService>().loadHistory();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokenService = context.watch<SunoTokenService>();
    final isLoggedIn = tokenService.isLoggedIn;
    final isCover = FoldUtils.isCoverScreen(context);
    final isFoldUnfolded = FoldUtils.isFoldUnfolded(context);
    final isMobile = isCover || MediaQuery.of(context).size.width < 700;

    String appTitle;
    if (isCover) {
      appTitle = '旋風 studio';
    } else if (isFoldUnfolded) {
      appTitle = '旋風 studio · Suno 專業工作台';
    } else {
      appTitle = '旋風 studio · Suno 專業上傳與歌詞拼音工作台';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF02AF4A).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.music_note, color: Color(0xFF02AF4A), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                appTitle,
                style: TextStyle(
                  fontSize: isCover ? 16 : 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        actions: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.cleaning_services, size: 20, color: Color(0xFFF87171)),
              tooltip: '清理 SUNO 碎片',
              onPressed: () => CleanSlicesDialog.show(context),
            )
          else
            OutlinedButton.icon(
              onPressed: () => CleanSlicesDialog.show(context),
              icon: const Icon(Icons.cleaning_services, size: 15, color: Color(0xFFF87171)),
              label: const Text('清理 SUNO 碎片', style: TextStyle(color: Color(0xFFF87171), fontSize: 12, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFEF4444)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          const SizedBox(width: 6),
          _buildStatusChip(isLoggedIn, isMobile: isMobile),
          SizedBox(width: isCover ? 6 : (isMobile ? 8 : 16)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF02AF4A),
            indicatorWeight: 3,
            labelColor: const Color(0xFF02AF4A),
            unselectedLabelColor: const Color(0xFF94A3B8),
            isScrollable: isCover,
            tabAlignment: isCover ? TabAlignment.start : null,
            tabs: [
              Tab(
                icon: const Icon(Icons.cloud_upload_outlined),
                text: isCover ? '音訊上傳' : (isFoldUnfolded ? '音訊上傳 (防審查)' : '音訊上傳 & 防審查'),
              ),
              Tab(
                icon: const Icon(Icons.translate),
                text: isCover ? '歌詞拼音' : (isFoldUnfolded ? '歌詞拼音工作室' : '歌詞拼音工作室 (港式/國語)'),
              ),
              Tab(
                icon: const Icon(Icons.history),
                text: isCover ? '上傳記錄' : (isFoldUnfolded ? '上傳記錄庫' : '上傳記錄庫 (改歌名/歌詞)'),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const MiniAudioPlayerBar(),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: 音訊上傳工作區 (保證極致流暢滑動)
          SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: FoldUtils.getHorizontalPadding(context),
              vertical: isCover ? 12 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSunoStatusBanner(context, tokenService, isMobile: isMobile),
                SizedBox(height: isCover ? 12 : 20),
                AudioUploadView(key: _uploadViewKey),
              ],
            ),
          ),

          // Tab 2: 歌詞拼音工作室
          LyricsPinyinView(
            onApplyToUpload: (lyrics) {
              // 切換回 Tab 1 並填入歌詞
              _tabController.animateTo(0);
              final uploadState = _uploadViewKey.currentState;
              if (uploadState != null) {
                try {
                  (uploadState as dynamic).setLyrics(lyrics);
                } catch (_) {}
              }
            },
          ),

          // Tab 3: 上傳記錄庫
          const UploadHistoryView(),
        ],
      ),
    );
  }

  Widget _buildStatusChip(bool isLoggedIn, {bool isMobile = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          final isNativeMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
          if (isNativeMobile) {
            SunoMobileLoginScreen.show(context);
          } else {
            SunoWebLoginDialog.show(context);
          }
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 5),
          decoration: BoxDecoration(
            color: isLoggedIn
                ? const Color(0xFF10B981).withValues(alpha: 0.2)
                : const Color(0xFFF59E0B).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isLoggedIn ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLoggedIn ? Icons.check_circle : Icons.warning_amber_rounded,
                size: 14,
                color: isLoggedIn ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 6),
                Text(
                  isLoggedIn ? 'Suno 已連接' : '未登入 (點擊登入)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isLoggedIn ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                ),
              ] else ...[
                const SizedBox(width: 4),
                Text(
                  isLoggedIn ? '已連線' : '未登入',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isLoggedIn ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSunoStatusBanner(BuildContext context, SunoTokenService tokenService, {bool isMobile = false}) {
    final isLoggedIn = tokenService.isLoggedIn;
    final token = tokenService.currentToken;

    final statusInfo = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isLoggedIn
                ? const Color(0xFF065F46).withValues(alpha: 0.5)
                : const Color(0xFF1E1B4B).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isLoggedIn ? Icons.verified_user : Icons.link_off,
            color: isLoggedIn ? const Color(0xFF34D399) : const Color(0xFF818CF8),
            size: isMobile ? 20 : 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isLoggedIn ? 'Suno 憑證已就緒 (在線)' : '尚未連接 Suno 帳號',
                style: TextStyle(fontSize: isMobile ? 14 : 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                isLoggedIn
                    ? '來源: ${token?.source ?? "系統同步"} · 狀態: 正常'
                    : '請使用瀏覽器登入 Suno 或貼上 Cookie/Token。',
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );

    final isNativeMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    final actionButtons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: () {
            if (isNativeMobile) {
              SunoMobileLoginScreen.show(context);
            } else {
              SunoWebLoginDialog.show(context);
            }
          },
          icon: Icon(
            isNativeMobile ? Icons.login : Icons.language,
            size: 15,
          ),
          label: Text(
            isLoggedIn
                ? (isNativeMobile ? '重新/切換帳號' : '管理/更新 Token')
                : (isNativeMobile ? '一鍵登入 Suno (免手動)' : '登入 Suno (取得 Token)'),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF02AF4A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        if (!kIsWeb)
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await tokenService.syncFromBrowserTokenFile();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? '已成功同步最新 Token！' : '暫無新 Token，目前憑證正常保持。'),
                    backgroundColor: ok ? const Color(0xFF059669) : const Color(0xFF475569),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.sync, size: 15),
            label: const Text('同步'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF475569)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        Tooltip(
          message: isNativeMobile ? '手動貼上 Token' : '一鍵剪貼簿導入或貼上 Token',
          child: OutlinedButton.icon(
            onPressed: () {
              if (isNativeMobile) {
                _showManualTokenDialog(context, tokenService);
              } else {
                SunoWebLoginDialog.show(context);
              }
            },
            icon: const Icon(Icons.content_paste, size: 15),
            label: Text(isNativeMobile ? '貼上 Token' : '導入 Token'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0xFF334155)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        if (!isMobile && !kIsWeb)
          Tooltip(
            message: '瀏覽器登錄助手 (Chrome / Edge 擴充)',
            child: OutlinedButton.icon(
              onPressed: () => _showExtensionInstallDialog(context, tokenService),
              icon: const Icon(Icons.extension, size: 15),
              label: const Text('登錄助手'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF38BDF8),
                side: const BorderSide(color: Color(0xFF0284C7)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                statusInfo,
                const SizedBox(height: 12),
                actionButtons,
              ],
            )
          : Row(
              children: [
                Expanded(child: statusInfo),
                const SizedBox(width: 16),
                actionButtons,
              ],
            ),
    );
  }

  void _showManualTokenDialog(BuildContext context, SunoTokenService tokenService) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('手動貼上 Suno Token', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: '請貼上 JWT 或 __session Cookie...',
            hintStyle: TextStyle(color: Colors.white38),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final raw = controller.text.trim();
              if (raw.length >= 80) {
                final token = SunoToken.fromRawToken(raw, source: 'manual-paste');
                await tokenService.updateToken(token);
                if (context.mounted) {
                  try {
                    context.read<UploadHistoryService>().syncFromSunoCloud(
                          token: token.token,
                          deviceId: token.deviceId,
                        );
                  } catch (_) {}
                }
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('確認導入'),
          ),
        ],
      ),
    );
  }

  void _showExtensionInstallDialog(BuildContext context, SunoTokenService tokenService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Row(
          children: [
            Icon(Icons.extension, color: Color(0xFF38BDF8), size: 24),
            SizedBox(width: 10),
            Text('旋風 studio 登錄助手 (Chrome / Edge)', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '安裝後，你在瀏覽器登入 Suno 時，Token 憑證將自動毫秒級無縫傳回旋風 studio，無需手動複製貼上。',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📌 簡單 3 步完成安裝：', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13)),
                    SizedBox(height: 8),
                    Text('1. 點擊下方【在 Finder 打開擴充資料夾】。', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
                    Text('2. 開啟 Chrome / Edge，網址列輸入 chrome://extensions 並開啟【開發者模式】。', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
                    Text('3. 點擊【載入未封裝項目】，選擇剛打開的 browser_extension 資料夾即可！', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await tokenService.openExtensionFolder();
            },
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('在 Finder 打開擴充資料夾'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await tokenService.openBrowserForLogin();
            },
            icon: const Icon(Icons.open_in_browser, size: 16),
            label: const Text('打開 Suno 登入頁'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF02AF4A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

