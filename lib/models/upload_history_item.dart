
class UploadHistoryItem {
  final String id;
  String title;
  String lyrics;
  String status;
  final String time;
  final String? clipId;
  final String? renderId;
  final String? songUrl;
  final String? audioUrl;
  final String? uploadMode;
  final String? sourcePath;
  final double? durationSec;

  UploadHistoryItem({
    required this.id,
    required this.title,
    this.lyrics = '',
    this.status = 'success',
    required this.time,
    this.clipId,
    this.renderId,
    this.songUrl,
    this.audioUrl,
    this.uploadMode = 'bypassWarp',
    this.sourcePath,
    this.durationSec,
  });

  String get effectiveSongUrl {
    if (songUrl != null && songUrl!.isNotEmpty) return songUrl!;
    final targetId = renderId ?? clipId;
    if (targetId != null && targetId.isNotEmpty) {
      return 'https://suno.com/song/$targetId';
    }
    return '';
  }

  factory UploadHistoryItem.fromJson(Map<String, dynamic> json) {
    // 兼容风聆Studio原版欄位或本App欄位
    final id = json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
    final title = json['title']?.toString() ?? '未命名歌曲';
    final lyrics = json['lyrics']?.toString() ?? json['prompt']?.toString() ?? '';
    final status = json['status']?.toString() ?? 'complete';
    final time = json['time']?.toString() ?? json['createdAt']?.toString() ?? DateTime.now().toString().substring(0, 19);
    final clipId = json['clipId']?.toString();
    final renderId = json['renderId']?.toString();
    final songUrl = json['songUrl']?.toString();
    final audioUrl = json['audioUrl']?.toString();
    final uploadMode = json['uploadMode']?.toString() ?? 'bypassWarp';
    final sourcePath = json['sourcePath']?.toString();
    final durationSec = (json['totalSeconds'] as num?)?.toDouble() ?? (json['durationSec'] as num?)?.toDouble();

    return UploadHistoryItem(
      id: id,
      title: title,
      lyrics: lyrics,
      status: status,
      time: time,
      clipId: clipId,
      renderId: renderId,
      songUrl: songUrl,
      audioUrl: audioUrl,
      uploadMode: uploadMode,
      sourcePath: sourcePath,
      durationSec: durationSec,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'lyrics': lyrics,
      'status': status,
      'time': time,
      'clipId': clipId,
      'renderId': renderId,
      'songUrl': effectiveSongUrl,
      'audioUrl': audioUrl,
      'uploadMode': uploadMode,
      'sourcePath': sourcePath,
      'durationSec': durationSec,
      'totalSeconds': durationSec,
    };
  }
}
