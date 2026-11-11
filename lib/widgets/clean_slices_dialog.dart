import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/suno_cleaner_service.dart';

class CleanSlicesDialog extends StatefulWidget {
  const CleanSlicesDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const CleanSlicesDialog(),
    );
  }

  @override
  State<CleanSlicesDialog> createState() => _CleanSlicesDialogState();
}

class _CleanSlicesDialogState extends State<CleanSlicesDialog> {
  final Set<String> _selectedClipIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
  }

  void _startScan() async {
    final cleaner = context.read<SunoCleanerService>();
    final slices = await cleaner.scanForSlices();
    setState(() {
      _selectedClipIds.clear();
      _selectedClipIds.addAll(slices.map((s) => s.clipId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cleaner = context.watch<SunoCleanerService>();
    final slices = cleaner.detectedSlices;

    final isMobile = MediaQuery.of(context).size.width < 650;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.cleaning_services, color: Color(0xFFF87171), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '清理 SUNO 歌曲切片碎片',
                  style: TextStyle(color: Colors.white, fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  isMobile ? '移走 4X 變速中間切片 · 完整成曲 100% 保留' : '移走 4X 變速中間切片素材 · 完整歌曲 100% 安全保留',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 600,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 安全保護橫幅
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF064E3B).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Color(0xFF34D399), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '安全保護規則生效中：系統已鎖定保護所有 Full Song 完整作品，僅針對中間上傳的 slice_XX 碎片進行清理。',
                      style: TextStyle(color: Color(0xFFA7F3D0), fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 當前狀態訊息
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  cleaner.statusMessage,
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (cleaner.isScanning || cleaner.isCleaning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: Color(0xFF38BDF8), strokeWidth: 2),
                  )
                else
                  TextButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF38BDF8)),
                    label: const Text('重新掃描', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // 碎片清單或空狀態
            Expanded(
              child: cleaner.isScanning && slices.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                  : slices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.done_all, size: 54, color: const Color(0xFF34D399).withValues(alpha: 0.7)),
                              const SizedBox(height: 12),
                              const Text(
                                'Suno 作品庫非常乾淨！',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '目前未發現任何殘留的切片碎片，所有完整歌曲均完好無損。',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: ListView.separated(
                            padding: const EdgeInsets.all(8),
                            itemCount: slices.length,
                            separatorBuilder: (ctx, i) => const Divider(color: Color(0xFF1E293B), height: 1),
                            itemBuilder: (ctx, i) {
                              final item = slices[i];
                              final isSelected = _selectedClipIds.contains(item.clipId);

                              return CheckboxListTile(
                                value: isSelected,
                                activeColor: const Color(0xFFEF4444),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                title: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('碎片', style: TextStyle(color: Color(0xFFF87171), fontSize: 11)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (item.durationSec != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '${item.durationSec!.toStringAsFixed(1)}s',
                                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  'ID: ${item.clipId.substring(0, 8)}... · ${item.createdAt}',
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontFamily: 'monospace'),
                                ),
                                onChanged: cleaner.isCleaning
                                    ? null
                                    : (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedClipIds.add(item.clipId);
                                          } else {
                                            _selectedClipIds.remove(item.clipId);
                                          }
                                        });
                                      },
                              );
                            },
                          ),
                          ),
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: cleaner.isCleaning ? null : () => Navigator.pop(context),
          child: const Text('關閉', style: TextStyle(color: Color(0xFF94A3B8))),
        ),
        if (slices.isNotEmpty)
          ElevatedButton.icon(
            onPressed: (cleaner.isCleaning || _selectedClipIds.isEmpty)
                ? null
                : () async {
                    final count = await cleaner.trashSlices(_selectedClipIds.toList());
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ 成功移除 $count 個切片碎片！Suno 庫已淨化，完整歌曲已完好保留。'),
                          backgroundColor: const Color(0xFF059669),
                        ),
                      );
                    }
                  },
            icon: cleaner.isCleaning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep, size: 18),
            label: Text(
              cleaner.isCleaning
                  ? '清理中...'
                  : '一鍵移除 (${_selectedClipIds.length} 個碎片)',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}
