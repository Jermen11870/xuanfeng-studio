import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';
import '../core/fold_utils.dart';

/// 屏幕底部懸浮/常駐音訊播放欄
/// 點擊歌曲後自動呈現，支援即時進度調整、暫停、恢復與關閉
class MiniAudioPlayerBar extends StatelessWidget {
  const MiniAudioPlayerBar({super.key});

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<AudioPlayerService>();

    // 若無音訊在播放或暫停中，則不顯示
    if (!playerService.isActive && !playerService.isLoading) {
      return const SizedBox.shrink();
    }

    final isCover = FoldUtils.isCoverScreen(context);
    final title = playerService.currentTitle ?? '正在播放音訊...';
    final currentPos = playerService.position;
    final totalDur = playerService.duration;

    final maxMs = totalDur.inMilliseconds > 0 ? totalDur.inMilliseconds.toDouble() : 1.0;
    final curMs = currentPos.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: Color(0xFF02AF4A), width: 2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isCover ? 10 : 18,
            vertical: isCover ? 6 : 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 頂部進度條 (極細條或 Slider)
              Row(
                children: [
                  Text(
                    _formatDuration(currentPos),
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'monospace'),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: const Color(0xFF02AF4A),
                        inactiveTrackColor: const Color(0xFF334155),
                        thumbColor: const Color(0xFF34D399),
                      ),
                      child: Slider(
                        value: curMs,
                        min: 0.0,
                        max: maxMs,
                        onChanged: (val) {
                          playerService.seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(totalDur),
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ),
              // 主控制列
              Row(
                children: [
                  // 動態旋轉音符或封面圖示
                  Container(
                    width: isCover ? 34 : 40,
                    height: isCover ? 34 : 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF02AF4A).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: playerService.isLoading
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF02AF4A)),
                            ),
                          )
                        : Icon(
                            playerService.isPlaying ? Icons.music_note : Icons.pause,
                            color: const Color(0xFF02AF4A),
                            size: isCover ? 18 : 22,
                          ),
                  ),
                  SizedBox(width: isCover ? 8 : 12),
                  // 歌曲標題
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isCover ? 13 : 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          playerService.isPlaying
                              ? '正在播放中 · 點擊暫停'
                              : (playerService.isPaused ? '已暫停 · 點擊恢復播放' : '載入中...'),
                          style: TextStyle(
                            color: playerService.isPlaying ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  // 倒退 5 秒
                  IconButton(
                    iconSize: isCover ? 20 : 22,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.replay_5, color: Color(0xFF94A3B8)),
                    tooltip: '倒退 5 秒',
                    onPressed: () {
                      final newPos = currentPos - const Duration(seconds: 5);
                      playerService.seek(newPos < Duration.zero ? Duration.zero : newPos);
                    },
                  ),
                  SizedBox(width: isCover ? 6 : 10),
                  // 播放 / 暫停 大按鈕
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF02AF4A),
                      foregroundColor: Colors.white,
                    ),
                    iconSize: isCover ? 20 : 24,
                    icon: Icon(playerService.isPlaying ? Icons.pause : Icons.play_arrow),
                    tooltip: playerService.isPlaying ? '暫停' : '播放',
                    onPressed: () {
                      if (playerService.isPlaying) {
                        playerService.pause();
                      } else {
                        playerService.resume();
                      }
                    },
                  ),
                  SizedBox(width: isCover ? 6 : 10),
                  // 快轉 5 秒
                  IconButton(
                    iconSize: isCover ? 20 : 22,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.forward_5, color: Color(0xFF94A3B8)),
                    tooltip: '快轉 5 秒',
                    onPressed: () {
                      final newPos = currentPos + const Duration(seconds: 5);
                      playerService.seek(newPos > totalDur ? totalDur : newPos);
                    },
                  ),
                  SizedBox(width: isCover ? 4 : 8),
                  // 關閉播放條
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                    tooltip: '停止並關閉播放條',
                    onPressed: () => playerService.stop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
