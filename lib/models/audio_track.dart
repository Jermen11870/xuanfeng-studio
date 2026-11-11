import 'dart:io';
import 'package:flutter/foundation.dart';

class AudioSlice {
  final int index;
  final String fileName;
  final String path;
  final double startSec;
  final double endSec;
  final double duration;
  String? uploadId;
  String? clipId;
  String status; // 'pending', 'uploading', 'complete', 'failed'

  AudioSlice({
    required this.index,
    required this.fileName,
    required this.path,
    required this.startSec,
    required this.endSec,
    required this.duration,
    this.uploadId,
    this.clipId,
    this.status = 'pending',
  });
}

class AudioTrack {
  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final double durationSeconds;
  final Uint8List? bytes;
  String title;
  String style;
  String lyrics;
  List<AudioSlice> slices;
  List<double> waveformPoints;

  AudioTrack({
    required this.filePath,
    required this.fileName,
    required this.fileSizeBytes,
    required this.durationSeconds,
    this.bytes,
    this.title = '',
    this.style = '',
    this.lyrics = '',
    List<AudioSlice>? slices,
    List<double>? waveformPoints,
  })  : slices = slices ?? [],
        waveformPoints = waveformPoints ?? [];

  String get formattedDuration {
    final totalSec = durationSeconds.round();
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get fileNameWithoutExt {
    final dot = fileName.lastIndexOf('.');
    return dot != -1 ? fileName.substring(0, dot) : fileName;
  }

  String get fileExtension {
    if (fileName.contains('.')) {
      return fileName.split('.').last.toUpperCase();
    }
    return filePath.split('.').last.toUpperCase();
  }

  bool get exists => kIsWeb ? (bytes != null && bytes!.isNotEmpty) : File(filePath).existsSync();
}
