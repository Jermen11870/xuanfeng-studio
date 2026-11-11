import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'audio_warp_processor.dart';

@JS('processAndSlice4XWeb')
external JSPromise<JSArray<JSObject>> _processAndSlice4XWeb(
  JSAny rawBytes,
  JSNumber speed,
  JSNumber sliceSec,
);

Future<List<PreparedSlice>> processAndSlice4XOnWeb(
  Uint8List audioBytes, {
  double speed = 4.0,
  double sliceSec = 10.0,
}) async {
  final promise = _processAndSlice4XWeb(
    audioBytes.toJS,
    speed.toJS,
    sliceSec.toJS,
  );

  final jsArray = await promise.toDart;
  final dartList = jsArray.toDart;
  final List<PreparedSlice> slices = [];

  for (final item in dartList) {
    final index = (item.getProperty('index'.toJS) as JSNumber).toDartInt;
    final fileName = (item.getProperty('fileName'.toJS) as JSString).toDart;
    final timelineStartSec = (item.getProperty('timelineStartSec'.toJS) as JSNumber).toDartDouble;
    final timelineEndSec = (item.getProperty('timelineEndSec'.toJS) as JSNumber).toDartDouble;
    final spedDurationSec = (item.getProperty('spedDurationSec'.toJS) as JSNumber).toDartDouble;
    final speedVal = (item.getProperty('speed'.toJS) as JSNumber).toDartDouble;
    final rawBytes = (item.getProperty('bytes'.toJS) as JSUint8Array).toDart;

    slices.add(
      PreparedSlice(
        index: index,
        filePath: 'web://$fileName',
        fileName: fileName,
        timelineStartSec: timelineStartSec,
        timelineEndSec: timelineEndSec,
        spedDurationSec: spedDurationSec,
        speed: speedVal,
        bytes: rawBytes,
      ),
    );
  }

  return slices;
}
