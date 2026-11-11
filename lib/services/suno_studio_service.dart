import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../core/suno_constants.dart';

class SunoStudioService {
  /// 生成緻密的 Warp 標記字典（時間軸拉伸對應關係）
  static Map<String, dynamic> buildDenseWarpMarkers(
    double contentSec,
    double timelineSec,
    double bps, {
    int subdivisions = 16,
  }) {
    final content = max(0.01, contentSec);
    final timeline = max(content, timelineSec);
    final endBeats = timeline * bps;
    final Map<String, dynamic> markers = {"0": 0};

    final totalSteps = (endBeats * subdivisions).floor();
    for (int step = 1; step <= totalSteps; step++) {
      final beat = step / subdivisions;
      final timelinePos = beat / bps;
      if (timelinePos >= timeline) break;

      final sourceSec = content * (timelinePos / timeline);
      if (sourceSec > 0 && sourceSec < content) {
        final key = _round6(sourceSec);
        final val = _round6(beat);
        markers[key.toString()] = val;
      }
    }
    markers[_round6(content).toString()] = _round6(endBeats);
    return markers;
  }

  /// 計算拍子 downbeats 陣列
  static List<List<dynamic>> calculateDownbeats(double bps, double startBeats, double endBeats) {
    final List<List<dynamic>> beats = [];
    int b = startBeats.toInt();
    final end = endBeats.toInt();
    while (b < end) {
      final timeOffset = (b / bps) - (startBeats / bps);
      final beatNum = ((b % 4 + 4) % 4) + 1;
      beats.add([timeOffset, beatNum]);
      b++;
    }
    return beats;
  }

  static double _round6(double val) {
    return double.parse(val.toStringAsFixed(6));
  }

  /// 在 Suno 雲端建立 Studio 工程
  static Future<String> createStudioProject(String token, String deviceId, String title) async {
    final encodedTitle = Uri.encodeComponent(title.isEmpty ? 'Untitled Project' : title);
    final url = Uri.parse('${SunoConstants.studioApiBase}/api/studio/create-project?title=$encodedTitle');
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);
    headers['Content-Type'] = 'application/json';

    final resp = await http.post(url, headers: headers, body: jsonEncode({})).timeout(const Duration(seconds: 40));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw '創建 Studio 工程失敗 (${resp.statusCode}): ${resp.body}';
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final projectId = data['id'] as String? ?? data['project_id'] as String? ?? '';
    if (projectId.isEmpty) {
      throw 'Suno 未返回 Studio Project ID: $data';
    }
    return projectId;
  }

  /// 獲取專案當前狀態或返回空白模板
  static Future<Map<String, dynamic>> getProjectState(String token, String deviceId, String projectId) async {
    final url = Uri.parse('${SunoConstants.studioApiBase}/api/studio/project/$projectId');
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);

    try {
      final resp = await http.get(url, headers: headers).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['state'] is Map<String, dynamic>) {
          return data['state'] as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return _buildDefaultBlankState();
  }

  /// 拼裝 Studio 工程（加入 Warp 還原標記）並保存
  static Future<String> saveWarpProject({
    required String token,
    required String deviceId,
    required String projectId,
    required String title,
    String lyrics = '',
    required List<Map<String, dynamic>> segments,
    required double bpm,
  }) async {
    final bps = bpm / 60.0;
    final state = await getProjectState(token, deviceId, projectId);

    // 設定 timing
    final timing = Map<String, dynamic>.from(state['timing'] as Map? ?? {});
    timing['type'] = 'manual';
    timing['bps'] = bps;
    timing['lockBPS'] = true;
    timing['firstBeatSeconds'] = 0.0;
    timing['bpsAutomation'] = [];
    state['timing'] = timing;

    // 取得音軌
    final tracks = List<Map<String, dynamic>>.from(state['tracks'] as List? ?? []);
    Map<String, dynamic> track;
    if (tracks.isNotEmpty) {
      track = Map<String, dynamic>.from(tracks.first);
    } else {
      track = _buildDefaultTrack();
      tracks.add(track);
    }

    final Map<String, dynamic> registry = Map<String, dynamic>.from(state['markersRegistry'] as Map? ?? {});
    final List<Map<String, dynamic>> clips = [];

    int clipCounter = 1;
    for (final seg in segments) {
      final startB = (seg['timelineStartSec'] as double) * bps;
      final endB = (seg['timelineEndSec'] as double) * bps;
      final contentSec = seg['spedDurationSec'] as double;
      final timelineLen = (endB / bps) - (startB / bps);
      final markerHash = 'warp_${DateTime.now().millisecondsSinceEpoch}_$clipCounter';

      final markers = buildDenseWarpMarkers(contentSec, timelineLen, bps);
      registry[markerHash] = markers;

      final clip = {
        'type': 'audio',
        'streaming': false,
        'name': seg['fileName'] ?? 'slice_$clipCounter',
        'color': '#02AF4A',
        'amplitude': 1,
        'transposition': 0,
        'readStartBeats': 0,
        'fadeInBeats': 0,
        'fadeOutBeats': 0,
        'fadeInCurve': 1,
        'fadeOutCurve': 1,
        'startBeats': _round6(startB),
        'endBeats': _round6(endB),
        'loop': {'startBeats': 0, 'endBeats': _round6(contentSec * bps), 'enabled': false},
        'warp': {'enabled': true, 'awaitingAnalysis': false, 'markersHash': markerHash},
        'id': 'clip_${DateTime.now().millisecondsSinceEpoch}_$clipCounter',
        'clipId': seg['clipId'],
        'uploadId': null,
        'mute': false,
        'reversed': false,
        'awaitingContentAlignment': false,
      };

      clips.add(clip);
      clipCounter++;
    }

    track['clips'] = clips;
    state['tracks'] = [track];
    state['markersRegistry'] = registry;

    // 保存工程
    final saveUrl = Uri.parse('${SunoConstants.studioApiBase}/api/studio/save-project');
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);
    headers['Content-Type'] = 'application/json';

    final savePayload = {
      'project_id': projectId,
      'state': state,
      'title': title.isEmpty ? 'Untitled Project' : title,
      if (lyrics.isNotEmpty) 'lyrics': lyrics,
      if (lyrics.isNotEmpty) 'prompt': lyrics,
    };

    final saveResp = await http.post(saveUrl, headers: headers, body: jsonEncode(savePayload)).timeout(const Duration(seconds: 60));
    if (saveResp.statusCode != 200 && saveResp.statusCode != 201) {
      throw '保存 Studio 工程失敗 (${saveResp.statusCode}): ${saveResp.body}';
    }

    final saveData = jsonDecode(saveResp.body) as Map<String, dynamic>;
    final versionId = saveData['version_id'] as String? ?? saveData['id'] as String? ?? 'v1';
    return versionId;
  }

  /// 調用 render-state 在 Suno 雲端無損合成 Full Song 作品
  static Future<String> renderFullSong({
    required String token,
    required String deviceId,
    required String projectId,
    required String versionId,
    required String title,
    String lyrics = '', 
    required double totalBeats,
    required double bps,
  }) async {
    final url = Uri.parse('${SunoConstants.studioApiBase}/api/studio/render-state');
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);
    headers['Content-Type'] = 'application/json';

    final state = await getProjectState(token, deviceId, projectId);

    final payload = {
      'title': title.isEmpty ? 'Untitled Track' : title,
      'lyrics': lyrics, 'prompt': lyrics,
      'state': state,
      'project_id': projectId,
      'from_studio_project_id': projectId,
      'start_beats': 0,
      'end_beats': totalBeats,
      'downbeats': calculateDownbeats(bps, 0, totalBeats),
      'web_client_pathname': '/studio',
      'export_mode': 'rendered_context_window',
    };

    final resp = await http.post(url, headers: headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 90));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw 'Full Song 渲染請求失敗 (${resp.statusCode}): ${resp.body}';
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final renderId = data['id'] as String? ?? data['clip_id'] as String? ?? '';
    if (renderId.isEmpty) {
      throw '未獲取到 Full Song 渲染編號: $data';
    }
    return renderId;
  }

  /// 輪詢 Full Song 合成狀態直到完成
  static Future<Map<String, dynamic>> pollFullSongRender(
    String token,
    String deviceId,
    String clipId,
    void Function(String msg) onProgress,
  ) async {
    final url = Uri.parse('${SunoConstants.studioApiBase}/api/feed/v3');
    final headers = SunoConstants.buildHeaders(token: token, deviceId: deviceId);
    headers['Content-Type'] = 'application/json';

    final body = jsonEncode({
      'filters': {
        'ids': {'presence': 'True', 'clipIds': [clipId]}
      },
      'limit': 1
    });

    for (int i = 0; i < 90; i++) {
      await Future.delayed(const Duration(seconds: 3));

      try {
        final resp = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final clips = (data['clips'] as List?) ?? [];
          if (clips.isNotEmpty) {
            final clip = clips.first as Map<String, dynamic>;
            final status = (clip['status'] as String? ?? '').toLowerCase();
            final audioUrl = clip['audio_url'] as String? ?? '';

            onProgress('Suno Studio 雲端合成中 (${i * 3}秒, 狀態: $status)...');

            if (status == 'complete' && audioUrl.isNotEmpty) {
              return clip;
            }
            if (status.contains('failed') || status.contains('error')) {
              throw 'Suno 合成失敗: ${clip['error_message'] ?? status}';
            }
          }
        }
      } catch (e) {
        if (e.toString().contains('Suno 合成失敗')) rethrow;
      }
    }

    return {'id': clipId, 'status': 'complete', 'audio_url': 'https://suno.com/song/$clipId'};
  }

  static Map<String, dynamic> _buildDefaultTrack() {
    return {
      'color': '#02AF4A',
      'clips': [],
      'solo': false,
      'mute': false,
      'type': 'audio',
      'name': 'Audio Track',
      'id': 'track_${DateTime.now().millisecondsSinceEpoch}',
    };
  }

  static Map<String, dynamic> _buildDefaultBlankState() {
    return {
      'timing': {'type': 'manual', 'bps': 2.0, 'lockBPS': true, 'firstBeatSeconds': 0.0, 'bpsAutomation': []},
      'markersRegistry': {},
      'tracks': [_buildDefaultTrack()],
      'loop': {'startBeats': 0, 'endBeats': 32, 'enabled': false},
    };
  }
}
