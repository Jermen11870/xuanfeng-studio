import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/suno_token.dart';
import '../services/suno_token_service.dart';
import '../services/upload_history_service.dart';

/// Suno Web / 電腦端登入助手對話框
class SunoWebLoginDialog extends StatefulWidget {
  const SunoWebLoginDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const SunoWebLoginDialog(),
    );
  }

  @override
  State<SunoWebLoginDialog> createState() => _SunoWebLoginDialogState();
}

class _SunoWebLoginDialogState extends State<SunoWebLoginDialog> {
  final TextEditingController _manualController = TextEditingController();
  bool _isProcessing = false;
  String? _errorMessage;

  static const String _consoleSnippet =
      '(async()=>{let t=null;try{t=await window.Clerk?.session?.getToken();}catch(e){}if(!t){const m=document.cookie.match(/__session=([^;]+)/);if(m)t=m[1];}if(!t){for(let i=0;i<localStorage.length;i++){const v=localStorage.getItem(localStorage.key(i));if(v&&v.startsWith("eyJ")&&v.includes(".")){t=v;break;}}}if(t){try{copy(t);}catch(e){}prompt("✅ 成功獲取最新 Suno Token！請按 Cmd+C 複製（剪貼簿已自動同步）：",t);}else{alert("❌ 找不到 Token！請確認您已在 suno.com 登入並位於 Suno 頁面！");}})();';

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  /// 一鍵從剪貼簿讀取並導入
  Future<void> _importFromClipboard() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipData?.text?.trim() ?? '';

      if (text.isEmpty) {
        setState(() {
          _errorMessage = '剪貼簿為空！請先複製 Suno Token 或執行提取腳本。';
          _isProcessing = false;
        });
        return;
      }

      await _processAndSaveToken(text, source: 'web-clipboard-oneclick');
    } catch (e) {
      setState(() {
        _errorMessage = '讀取剪貼簿失敗：$e';
        _isProcessing = false;
      });
    }
  }

  /// 手動輸入框導入
  Future<void> _importFromInput() async {
    final text = _manualController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = '請輸入或貼上 Token / Cookie 字串。';
      });
      return;
    }
    await _processAndSaveToken(text, source: 'web-manual-input');
  }

  Future<void> _processAndSaveToken(String rawText, {required String source}) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    final token = SunoToken.fromRawToken(rawText, source: source);
    if (!token.isValid) {
      setState(() {
        _errorMessage = '憑證無效或已過期，請確認是否為 Suno 的 __session Cookie 或 JWT。';
        _isProcessing = false;
      });
      return;
    }

    final tokenService = context.read<SunoTokenService>();
    await tokenService.updateToken(token);

    final isValid = await tokenService.validateTokenWithSuno();
    if (!isValid) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Suno 伺服器驗證失敗 (401 Unauthorized)：此 Token 已過期或無效！\n請於 Suno 網頁確認已登入後，再次執行提取腳本。';
          _isProcessing = false;
        });
      }
      return;
    }

    // 立即觸發一次雲端歷史記錄同步
    try {
      if (mounted) {
        context.read<UploadHistoryService>().syncFromSunoCloud(
              token: token.token,
              deviceId: token.deviceId,
            );
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Suno 登入成功！Token 已成功導入並持久保存！'),
          backgroundColor: Color(0xFF059669),
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  /// 複製一秒提取代碼
  Future<void> _copyConsoleSnippet() async {
    await Clipboard.setData(const ClipboardData(text: _consoleSnippet));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚡ 提取代碼已複製！在 Suno 登入頁按 F12 (Console) 貼上 Enter 即可自動抓取！'),
          backgroundColor: Color(0xFF0284C7),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokenService = context.watch<SunoTokenService>();
    final isLoggedIn = tokenService.isLoggedIn;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.language, color: Color(0xFF38BDF8), size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Suno 網頁版登入助手',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white60, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 狀態提示橫幅
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isLoggedIn
                      ? const Color(0xFF065F46).withValues(alpha: 0.35)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isLoggedIn ? const Color(0xFF10B981) : const Color(0xFF334155),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isLoggedIn ? Icons.check_circle : Icons.info_outline,
                      color: isLoggedIn ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isLoggedIn
                            ? '目前已登入 (${tokenService.currentToken?.source ?? 'Suno Token'} 保持中)'
                            : '當前未登入 Suno，請使用下方步驟 1 秒取得 Token。',
                        style: TextStyle(
                          color: isLoggedIn ? const Color(0xFF34D399) : Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 錯誤訊息提示
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // 步驟 1 與 2：雙按鈕列
              const Text(
                '【極速獲取流程】只需 2 步：',
                style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => tokenService.openBrowserForLogin(),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('① 打開 Suno 登入頁'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyConsoleSnippet,
                      icon: const Icon(Icons.code, size: 16),
                      label: const Text('② 複製 1 秒提取腳本'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFBBF24),
                        side: const BorderSide(color: Color(0xFFD97706)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
              const Text(
                '💡 提示：在 Suno 登入完成後，按 F12 (Console) 貼上腳本並 Enter，Token 將自動彈出並複製。',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.4),
              ),

              const SizedBox(height: 16),

              // 步驟 3：一鍵導入大按鈕
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _importFromClipboard,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.content_paste_go, size: 18),
                  label: const Text(
                    '📋 一鍵從剪貼簿讀取並登入',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 備用通道：手動貼上輸入框
              Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFF334155))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '或 手動貼上憑證',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                    ),
                  ),
                  const Expanded(child: Divider(color: Color(0xFF334155))),
                ],
              ),

              const SizedBox(height: 12),

              TextField(
                controller: _manualController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: '支援貼上 JWT、__session Cookie 或整串 Cookie...',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      '📌 最穩手工法：F12 ➔ Network ➔ 搜尋「api」➔ Request Headers 複製 authorization 貼入',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _importFromInput,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('手動解析導入'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!kIsWeb)
          TextButton.icon(
            onPressed: () => tokenService.openExtensionFolder(),
            icon: const Icon(Icons.extension, size: 15, color: Color(0xFF38BDF8)),
            label: const Text('Chrome 擴充資料夾', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉', style: TextStyle(color: Colors.white60)),
        ),
      ],
    );
  }
}
