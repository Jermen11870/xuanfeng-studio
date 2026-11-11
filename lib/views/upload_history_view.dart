import 'package:flutter/foundation.dart';
import '../widgets/clean_slices_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/fold_utils.dart';
import '../models/upload_history_item.dart';
import '../services/audio_player_service.dart';
import '../services/suno_token_service.dart';
import '../services/upload_history_service.dart';

class UploadHistoryView extends StatelessWidget {
  const UploadHistoryView({super.key});

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final historyService = context.watch<UploadHistoryService>();
    final tokenService = context.watch<SunoTokenService>();
    final playerService = context.watch<AudioPlayerService>();
    final items = historyService.items;

    final isCover = FoldUtils.isCoverScreen(context);
    final isFoldUnfolded = FoldUtils.isFoldUnfolded(context);
    final isMobile = isCover || MediaQuery.of(context).size.width < 650;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Padding(
        padding: EdgeInsets.all(FoldUtils.getHorizontalPadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題與操作欄 (響應式排版)
            if (isMobile) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Suno 上傳歷史記錄',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '共 ${items.length} 首已上傳作品 · 可直接改歌名、歌詞與打開連結',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: historyService.isSyncingCloud
                            ? null
                            : () async {
                                final token = tokenService.currentToken;
                                if (token == null || !token.isValid) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('請先在頂部登入 Suno 帳號，方可從雲端同步歷史歌曲'),
                                      backgroundColor: Color(0xFFF59E0B),
                                    ),
                                  );
                                  return;
                                }
                                final count = await historyService.syncFromSunoCloud(
                                  token: token.token,
                                  deviceId: token.deviceId,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(count > 0 ? '成功同步 $count 首 Suno 雲端成曲！已自動過濾所有碎片。' : '雲端歷史已是最新，未發現新成曲。'),
                                      backgroundColor: const Color(0xFF059669),
                                    ),
                                  );
                                }
                              },
                        icon: historyService.isSyncingCloud
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.cloud_sync, size: 14),
                        label: Text(historyService.isSyncingCloud ? '同步中...' : '從雲端同步 (過濾碎片)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF02AF4A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => CleanSlicesDialog.show(context),
                        icon: const Icon(Icons.delete_sweep, size: 14),
                        label: const Text('清理碎片 (保留完整歌曲)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7F1D1D),
                          foregroundColor: const Color(0xFFFCA5A5),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await historyService.loadHistory();
                          final token = tokenService.currentToken;
                          if (token != null && token.isValid) {
                            final count = await historyService.syncFromSunoCloud(
                              token: token.token,
                              deviceId: token.deviceId,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(count > 0 ? '已同步 $count 首 Suno 雲端成曲！' : (kIsWeb ? '已重新整理本地資料庫 (Web 瀏覽器受同源限制，在手機 APK 可直連拉取全部雲端歷史)' : '已重新整理，目前已是最新記錄。')),
                                  backgroundColor: const Color(0xFF0284C7),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已重新整理本地記錄庫。登入 Suno 後可同步雲端成曲。'),
                                  backgroundColor: Color(0xFF334155),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('重新整理'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF334155)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Suno 上傳歷史記錄',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '共 ${items.length} 首已上傳作品 · 可直接改歌名、歌詞與打開 Suno 連結',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: historyService.isSyncingCloud
                            ? null
                            : () async {
                                final token = tokenService.currentToken;
                                if (token == null || !token.isValid) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('請先登入 Suno 帳號，方可從雲端同步歷史歌曲'),
                                      backgroundColor: Color(0xFFF59E0B),
                                    ),
                                  );
                                  return;
                                }
                                final count = await historyService.syncFromSunoCloud(
                                  token: token.token,
                                  deviceId: token.deviceId,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(count > 0 ? '成功同步 $count 首 Suno 雲端成曲！已自動過濾所有碎片。' : '雲端歷史已是最新，未發現新成曲。'),
                                      backgroundColor: const Color(0xFF059669),
                                    ),
                                  );
                                }
                              },
                        icon: historyService.isSyncingCloud
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.cloud_sync, size: 16),
                        label: Text(historyService.isSyncingCloud ? '正在同步雲端...' : '從 Suno 雲端同步歷史 (過濾碎片)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF02AF4A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => CleanSlicesDialog.show(context),
                        icon: const Icon(Icons.delete_sweep, size: 16),
                        label: const Text('移除 SUNO 碎片 (只留完整歌曲)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7F1D1D),
                          foregroundColor: const Color(0xFFFCA5A5),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await historyService.loadHistory();
                          final token = tokenService.currentToken;
                          if (token != null && token.isValid) {
                            final count = await historyService.syncFromSunoCloud(
                              token: token.token,
                              deviceId: token.deviceId,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(count > 0 ? '已同步 $count 首 Suno 雲端成曲！' : (kIsWeb ? '已重新整理本地資料庫 (Web 瀏覽器受同源限制，在手機 APK 可直連拉取全部雲端歷史)' : '已重新整理，目前已是最新記錄。')),
                                  backgroundColor: const Color(0xFF0284C7),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已重新整理本地記錄庫。登入 Suno 後可同步雲端成曲。'),
                                  backgroundColor: Color(0xFF334155),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('重新整理記錄'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF334155)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            SizedBox(height: isMobile ? 12 : 20),

            // 搜尋欄
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                onChanged: historyService.setSearchKeyword,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜尋歌名、歌詞關鍵字或 Clip ID...',
                  hintStyle: const TextStyle(color: Color(0xFF64748B)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
                  suffixIcon: historyService.searchKeyword.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Color(0xFF94A3B8)),
                          onPressed: () => historyService.setSearchKeyword(''),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 列表主體
            Expanded(
              child: historyService.isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF02AF4A)))
                  : RefreshIndicator(
                      color: const Color(0xFF02AF4A),
                      backgroundColor: const Color(0xFF1E293B),
                      onRefresh: () async {
                        final token = tokenService.currentToken;
                        if (token != null && token.isValid) {
                          await historyService.syncFromSunoCloud(
                            token: token.token,
                            deviceId: token.deviceId,
                          );
                        } else {
                          await historyService.loadHistory();
                        }
                      },
                      child: items.isEmpty
                          ? _buildEmptyState(context, historyService, tokenService)
                          : _buildHistoryListOrGrid(context, items, historyService, tokenService, playerService, isFoldUnfolded),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 針對 Samsung Z Fold 7 內大屏（或平板）使用雙欄排版，外屏或窄機使用單欄
  Widget _buildHistoryListOrGrid(
    BuildContext context,
    List<UploadHistoryItem> items,
    UploadHistoryService service,
    SunoTokenService tokenService,
    AudioPlayerService playerService,
    bool isFoldUnfolded,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final useTwoColumns = isFoldUnfolded || screenWidth >= 750;

    if (useTwoColumns) {
      // 雙欄流式瀑布分佈，完全防止高度不一造成的溢出
      final leftItems = <UploadHistoryItem>[];
      final rightItems = <UploadHistoryItem>[];
      for (int i = 0; i < items.length; i++) {
        if (i % 2 == 0) {
          leftItems.add(items[i]);
        } else {
          rightItems.add(items[i]);
        }
      }

      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: leftItems.map((it) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildHistoryCard(context, it, service, tokenService, playerService),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                children: rightItems.map((it) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildHistoryCard(context, it, service, tokenService, playerService),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }

    // 單欄列表 (外前屏或常規手機)
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (ctx, i) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        return _buildHistoryCard(context, items[i], service, tokenService, playerService);
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    UploadHistoryService historyService,
    SunoTokenService tokenService,
  ) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music_outlined, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text(
              '暫無上傳歷史記錄',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '如果你曾喺 Mac 或其他地方上傳過歌曲，可點擊下方直接從 Suno 雲端同步返落嚟：',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: historyService.isSyncingCloud
                  ? null
                  : () async {
                      final token = tokenService.currentToken;
                      if (token == null || !token.isValid) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('請先在頂部登入 Suno 帳號，方可從雲端同步歷史歌曲'),
                            backgroundColor: Color(0xFFF59E0B),
                          ),
                        );
                        return;
                      }
                      final count = await historyService.syncFromSunoCloud(
                        token: token.token,
                        deviceId: token.deviceId,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(count > 0 ? '成功同步 $count 首 Suno 雲端成曲！已自動過濾所有碎片。' : '雲端歷史已是最新，未發現新成曲。'),
                            backgroundColor: const Color(0xFF059669),
                          ),
                        );
                      }
                    },
              icon: historyService.isSyncingCloud
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_sync, size: 16),
              label: Text(historyService.isSyncingCloud ? '正在同步雲端...' : '從 Suno 雲端拉取所有作品 (自動剔除碎片)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF02AF4A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(
    BuildContext context,
    UploadHistoryItem item,
    UploadHistoryService service,
    SunoTokenService tokenService,
    AudioPlayerService playerService,
  ) {
    final hasLyrics = item.lyrics.trim().isNotEmpty;
    final isBypass = item.uploadMode == 'bypassWarp' || item.uploadMode == 'split';
    final isCover = FoldUtils.isCoverScreen(context);

    final isCurrentPlaying = playerService.isPlaying && playerService.currentId == item.id;
    final isCurrentPaused = playerService.isPaused && playerService.currentId == item.id;
    final isCurrentActive = playerService.currentId == item.id;
    final isThisLoading = playerService.isLoading && playerService.currentId == item.id;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentActive ? const Color(0xFF02AF4A) : Colors.white.withValues(alpha: 0.08),
          width: isCurrentActive ? 1.5 : 1.0,
        ),
        boxShadow: isCurrentActive
            ? [
                BoxShadow(
                  color: const Color(0xFF02AF4A).withValues(alpha: 0.15),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.all(isCover ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：播放按鈕、歌名、模式標籤、操作
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 互動播放按鈕 (點擊播放/暫停音檔)
              InkWell(
                onTap: () async {
                  try {
                    await playerService.togglePlayHistoryItem(item);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('無法播放此音檔：$e'), backgroundColor: const Color(0xFFEF4444)),
                      );
                    }
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: isCover ? 40 : 44,
                  height: isCover ? 40 : 44,
                  decoration: BoxDecoration(
                    color: isCurrentPlaying
                        ? const Color(0xFF02AF4A)
                        : (isBypass
                            ? const Color(0xFF02AF4A).withValues(alpha: 0.15)
                            : const Color(0xFF38BDF8).withValues(alpha: 0.15)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: isThisLoading
                      ? const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                        )
                      : Icon(
                          isCurrentPlaying
                              ? Icons.pause
                              : (isCurrentPaused ? Icons.play_arrow : (isBypass ? Icons.play_circle_fill : Icons.music_note)),
                          color: isCurrentPlaying
                              ? Colors.white
                              : (isBypass ? const Color(0xFF02AF4A) : const Color(0xFF38BDF8)),
                          size: isCover ? 22 : 24,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => playerService.togglePlayHistoryItem(item),
                            child: Text(
                              item.title,
                              style: TextStyle(
                                color: isCurrentActive ? const Color(0xFF34D399) : Colors.white,
                                fontSize: isCover ? 14 : 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isBypass
                                ? const Color(0xFF02AF4A).withValues(alpha: 0.2)
                                : const Color(0xFF38BDF8).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isBypass ? '4X 防審查' : '原樣直傳',
                            style: TextStyle(
                              color: isBypass ? const Color(0xFF02AF4A) : const Color(0xFF38BDF8),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                          '上傳: ${item.time.length > 10 ? item.time.substring(5, 16) : item.time}',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                        if (item.durationSec != null)
                          Text(
                            '時長: ${item.durationSec!.toStringAsFixed(0)}秒',
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                        if (item.sourcePath != null && item.sourcePath!.isNotEmpty)
                          const Text(
                            '本地檔',
                            style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ★ 正在播放該曲目時的微型即時進度條 ★
          if (isCurrentActive) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF02AF4A).withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(playerService.position),
                        style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontFamily: 'monospace'),
                      ),
                      Row(
                        children: [
                          Icon(isCurrentPlaying ? Icons.volume_up : Icons.volume_mute, size: 14, color: const Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Text(
                            isCurrentPlaying ? '播放中' : '已暫停',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ],
                      ),
                      Text(
                        _formatDuration(playerService.duration),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                      activeTrackColor: const Color(0xFF02AF4A),
                      inactiveTrackColor: const Color(0xFF334155),
                      thumbColor: const Color(0xFF34D399),
                    ),
                    child: Slider(
                      value: playerService.position.inMilliseconds.toDouble().clamp(
                            0.0,
                            playerService.duration.inMilliseconds > 0 ? playerService.duration.inMilliseconds.toDouble() : 1.0,
                          ),
                      min: 0.0,
                      max: playerService.duration.inMilliseconds > 0 ? playerService.duration.inMilliseconds.toDouble() : 1.0,
                      onChanged: (val) {
                        playerService.seek(Duration(milliseconds: val.toInt()));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 歌詞預覽區（如果有）
          if (hasLyrics) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Text(
                item.lyrics,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const SizedBox(height: 10),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 8),

          // 操作按鈕列 (Wrap 自適應換行，防止窄屏溢出)
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              // 播放/暫停按鈕
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await playerService.togglePlayHistoryItem(item);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('無法播放此音檔：$e'), backgroundColor: const Color(0xFFEF4444)),
                      );
                    }
                  }
                },
                icon: Icon(
                  isCurrentPlaying ? Icons.pause : Icons.play_arrow,
                  size: 14,
                  color: isCurrentPlaying ? const Color(0xFF34D399) : const Color(0xFF02AF4A),
                ),
                label: Text(
                  isCurrentPlaying ? '暫停' : (isCurrentPaused ? '繼續' : '播放音檔'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isCurrentPlaying ? const Color(0xFF34D399) : const Color(0xFF02AF4A),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isCurrentPlaying ? const Color(0xFF34D399) : const Color(0xFF02AF4A).withValues(alpha: 0.6),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),

              // 編輯歌名與歌詞按鈕
              OutlinedButton.icon(
                onPressed: () => _showEditDialog(context, item, service, tokenService),
                icon: const Icon(Icons.edit_note, size: 14),
                label: const Text('改名/歌詞'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFCBD5E1),
                  side: const BorderSide(color: Color(0xFF475569)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),

              // 複製連結
              if (item.effectiveSongUrl.isNotEmpty)
                IconButton(
                  tooltip: '複製 Suno 連結',
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.copy, size: 15, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.effectiveSongUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已複製 Suno 歌曲連結至剪貼簿！')),
                    );
                  },
                ),

              // 刪除記錄按鈕
              IconButton(
                tooltip: '刪除此記錄',
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.delete_outline, size: 15, color: Color(0xFFEF4444)),
                onPressed: () => _confirmDelete(context, item, service),
              ),

              // 打開 SUNO 連結 (綠色按鈕)
              if (item.effectiveSongUrl.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => service.openSongUrl(item),
                  icon: const Icon(Icons.open_in_browser, size: 13),
                  label: const Text('打開歌曲'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF02AF4A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 彈出編輯歌名與歌詞對話框
  void _showEditDialog(
    BuildContext context,
    UploadHistoryItem item,
    UploadHistoryService service,
    SunoTokenService tokenService,
  ) {
    final titleController = TextEditingController(text: item.title);
    final lyricsController = TextEditingController(text: item.lyrics);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.edit, color: Color(0xFF02AF4A), size: 22),
              SizedBox(width: 10),
              Text('編輯歌曲資訊', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('歌曲名稱', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF02AF4A)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('歌曲歌詞 (Prompt / Lyrics)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: lyricsController,
                    maxLines: 8,
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                    decoration: InputDecoration(
                      hintText: '輸入或貼上完整歌詞...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B)),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF02AF4A)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.cloud_sync, color: Color(0xFF02AF4A), size: 14),
                      SizedBox(width: 6),
                      Text(
                        '保存時將自動同步更新至 Suno 雲端平台',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                    ],
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
                final newTitle = titleController.text.trim();
                final newLyrics = lyricsController.text.trim();

                final token = tokenService.currentToken;
                await service.updateItem(
                  id: item.id,
                  newTitle: newTitle.isEmpty ? item.title : newTitle,
                  newLyrics: newLyrics,
                  token: token?.token,
                  deviceId: token?.deviceId,
                );

                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✓ 歌名與歌詞已成功更新並同步至 Suno！')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF02AF4A),
                foregroundColor: Colors.white,
              ),
              child: const Text('保存並同步'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, UploadHistoryItem item, UploadHistoryService service) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('確認刪除記錄？', style: TextStyle(color: Colors.white)),
          content: Text('確定要從本地歷史中移除《${item.title}》嗎？', style: const TextStyle(color: Color(0xFFCBD5E1))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              onPressed: () {
                service.deleteItem(item.id);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
              child: const Text('確認刪除'),
            ),
          ],
        );
      },
    );
  }
}
