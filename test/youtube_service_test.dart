import 'package:flutter_test/flutter_test.dart';
import 'package:fengling_studio_flutter/services/audio_track_service.dart';
import 'package:fengling_studio_flutter/services/youtube_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YoutubeAudioService URL Validation Tests', () {
    final audioTrackService = AudioTrackService();
    final ytService = YoutubeAudioService(audioTrackService: audioTrackService);

    test('正確識別各類 YouTube 網址格式', () {
      expect(ytService.isValidYoutubeUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
      expect(ytService.isValidYoutubeUrl('http://youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
      expect(ytService.isValidYoutubeUrl('https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(ytService.isValidYoutubeUrl('https://www.youtube.com/shorts/dQw4w9WgXcQ'), isTrue);
      expect(ytService.isValidYoutubeUrl('https://m.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
    });

    test('排除非法網址', () {
      expect(ytService.isValidYoutubeUrl('https://google.com'), isFalse);
      expect(ytService.isValidYoutubeUrl(''), isFalse);
      expect(ytService.isValidYoutubeUrl('random text'), isFalse);
      expect(ytService.isValidYoutubeUrl('https://suno.com/song/12345'), isFalse);
    });
  });
}
