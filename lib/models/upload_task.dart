enum UploadStage {
  idle,
  preparing,
  uploadingS3,
  cloudProcessing,
  initializingClip,
  complete,
  failed,
}

class UploadTask {
  final String id;
  final String fileName;
  String title;
  String lyrics;
  String cantoneseLyrics;
  String mandarinLyrics;
  final double durationSec;
  UploadStage stage;
  double progress; // 0.0 to 1.0
  String statusMessage;
  String? clipId;
  String? s3Id;
  String? audioUrl;
  String? errorMessage;
  final List<String> logs;
  final DateTime createdAt;

  UploadTask({
    required this.id,
    required this.fileName,
    this.title = '',
    this.lyrics = '',
    this.cantoneseLyrics = '',
    this.mandarinLyrics = '',
    required this.durationSec,
    this.stage = UploadStage.idle,
    this.progress = 0.0,
    this.statusMessage = '準備就緒',
    this.clipId,
    this.s3Id,
    this.audioUrl,
    this.errorMessage,
    List<String>? logs,
    DateTime? createdAt,
  })  : logs = logs ?? [],
        createdAt = createdAt ?? DateTime.now();

  void addLog(String message) {
    final timeStr = DateTime.now().toLocal().toString().split(' ')[1].split('.')[0];
    logs.add('[$timeStr] $message');
  }

  bool get isProcessing =>
      stage != UploadStage.idle &&
      stage != UploadStage.complete &&
      stage != UploadStage.failed;

  bool get isSuccess => stage == UploadStage.complete;
  bool get isFailed => stage == UploadStage.failed;
}
