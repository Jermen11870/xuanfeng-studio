import 'dart:typed_data';
import 'audio_warp_processor.dart';

Future<List<PreparedSlice>> processAndSlice4XOnWeb(
  Uint8List audioBytes, {
  double speed = 4.0,
  double sliceSec = 10.0,
}) async {
  throw UnsupportedError('processAndSlice4XOnWeb 僅支援 Web 平台');
}
