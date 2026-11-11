import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/fold_utils.dart';
import '../models/audio_track.dart';
import '../services/audio_player_service.dart';

class WaveformTrackWidget extends StatelessWidget {
  final AudioTrack track;
  final VoidCallback onClear;

  const WaveformTrackWidget({
    super.key,
    required this.track,
    required this.onClear,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<AudioPlayerService>();
    final isCover = FoldUtils.isCoverScreen(context);

    final trackId = track.filePath.isNotEmpty ? track.filePath : track.fileName;
    final isPlaying = playerService.isPlaying && playerService.currentId == trackId;
    final isPaused = playerService.isPaused && playerService.currentId == trackId;
    final isActive = playerService.currentId == trackId;
    final isThisLoading = playerService.isLoading && playerService.currentId == trackId;

    return Container(
      padding: EdgeInsets.all(isCover ? 12 : 18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? const Color(0xFF02AF4A) : const Color(0xFF334155),
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頂部檔案資訊、播放試聽與刪除
          Row(
            children: [
              // 播放/暫停 按鈕
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: isPlaying ? const Color(0xFF02AF4A) : const Color(0xFF334155),
                  foregroundColor: isPlaying ? Colors.white : const Color(0xFF38BDF8),
                  padding: EdgeInsets.all(isCover ? 6 : 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                iconSize: isCover ? 20 : 22,
                tooltip: isPlaying ? '暫停本地試聽' : '播放本地音檔',
                onPressed: () async {
                  try {
                    await playerService.togglePlayTrack(track);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('無法播放此本地音檔：$e'), backgroundColor: const Color(0xFFEF4444)),
                      );
                    }
                  }
                },
                icon: isThisLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              const SizedBox(width: 8),

              // 格式標籤
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  track.fileExtension,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.cyanAccent,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 檔名
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.fileName,
                      style: TextStyle(
                        fontSize: isCover ? 13 : 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.formattedDuration} · ${track.formattedSize}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),

              // 移除按鈕
              IconButton(
                onPressed: () {
                  if (isActive) {
                    playerService.stop();
                  }
                  onClear();
                },
                icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                tooltip: '移除音軌',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          // 若正在播放該本地音軌，顯示進度時間
          if (isActive) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '播放進度: ${_formatDuration(playerService.position)}',
                  style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontFamily: 'monospace'),
                ),
                Text(
                  isPlaying ? '正在試聽本地音檔...' : (isPaused ? '已暫停' : ''),
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                Text(
                  _formatDuration(playerService.duration),
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),

          // 視覺化波形音軌條
          Container(
            height: isCover ? 56 : 68,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  isPlaying ? Icons.graphic_eq : Icons.audiotrack,
                  color: isPlaying ? const Color(0xFF34D399) : Colors.cyanAccent,
                  size: isCover ? 20 : 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomPaint(
                    size: const Size(double.infinity, 50),
                    painter: _WaveformPainter(
                      points: track.waveformPoints,
                      color: isPlaying ? const Color(0xFF34D399) : const Color(0xFF02AF4A),
                    ),
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

class _WaveformPainter extends CustomPainter {
  final List<double> points;
  final Color color;

  _WaveformPainter({
    required this.points,
    this.color = const Color(0xFF02AF4A),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      // 繪製預設佔位線
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      final count = 30;
      final spacing = size.width / count;
      final midY = size.height / 2;

      for (int i = 0; i < count; i++) {
        final x = i * spacing + spacing / 2;
        canvas.drawLine(Offset(x, midY - 4), Offset(x, midY + 4), paint);
      }
      return;
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final barWidth = 3.0;
    final gap = 2.0;
    final totalBarWidth = barWidth + gap;
    final maxBars = (size.width / totalBarWidth).floor();

    final step = points.length / maxBars;
    final midY = size.height / 2;
    final maxAmp = size.height * 0.45;

    for (int i = 0; i < maxBars; i++) {
      final sampleIndex = (i * step).floor().clamp(0, points.length - 1);
      final amplitude = points[sampleIndex].clamp(0.05, 1.0);
      final barHeight = amplitude * maxAmp;

      final x = i * totalBarWidth + barWidth / 2;
      canvas.drawLine(
        Offset(x, midY - barHeight),
        Offset(x, midY + barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}
