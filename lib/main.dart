import 'services/suno_cleaner_service.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/audio_track_service.dart';
import 'services/suno_auth_service.dart';
import 'services/suno_token_service.dart';
import 'services/suno_upload_service.dart';
import 'services/upload_history_service.dart';
import 'views/home_screen.dart';

import 'services/audio_player_service.dart';
import 'services/youtube_audio_service.dart';

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    if (runWebViewTitleBarWidget(args)) {
      return;
    }
  }

  final tokenService = SunoTokenService();
  final authService = SunoAuthService(tokenService: tokenService);
  final trackService = AudioTrackService();
  final historyService = UploadHistoryService();
  final audioPlayerService = AudioPlayerService();
  final uploadService = SunoUploadService(
    tokenService: tokenService,
    historyService: historyService,
  );
  final cleanerService = SunoCleanerService(
    tokenService: tokenService,
    historyService: historyService,
  );
  final ytService = YoutubeAudioService(audioTrackService: trackService);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: tokenService),
        ChangeNotifierProvider.value(value: trackService),
        ChangeNotifierProvider.value(value: uploadService),
        ChangeNotifierProvider.value(value: historyService),
        ChangeNotifierProvider.value(value: cleanerService),
        ChangeNotifierProvider.value(value: ytService),
        ChangeNotifierProvider.value(value: audioPlayerService),
      ],
      child: FenglingApp(authService: authService),
    ),
  );
}

class FenglingApp extends StatelessWidget {
  final SunoAuthService authService;

  const FenglingApp({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '旋風 studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF02AF4A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(authService: authService),
    );
  }
}
