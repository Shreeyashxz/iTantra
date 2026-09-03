import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'alerts/alert_broadcaster.dart';
import 'alerts/alert_receiver.dart';
import 'controllers/history_controller.dart';
import 'controllers/peer_controller.dart';
import 'controllers/settings_controller.dart';
import 'controllers/transceiver_controller.dart';
import 'data/app_database.dart';
import 'network/transceiver_manager.dart';
import 'network/wifi_mesh_manager.dart';
import 'speech/audio_recorder_service.dart';
import 'speech/comm_pipeline.dart';
import 'speech/language_pack_manager.dart';
import 'speech/sherpa_onnx_speech_engine.dart';
import 'speech/silero_vad_engine.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize sherpa-onnx native bindings (loads C++ shared library from exe dir)
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    sherpa.initBindings(exeDir);
  } catch (_) {
    sherpa.initBindings();
  }

  // Core singletons (matching Hilt AppModule / SpeechModule / TransportModule / DatabaseModule)
  final database = AppDatabase.instance;
  final languagePackManager = LanguagePackManager();
  final audioRecorder = AudioRecorderService();
  final vadEngine = SileroVadEngine();
  final speechEngine = SherpaOnnxSpeechEngine(languagePackManager: languagePackManager);
  final transceiverManager = TransceiverManager();
  final meshManager = WifiMeshManager(transceiverManager: transceiverManager);
  final alertBroadcaster = AlertBroadcaster(transceiverManager: transceiverManager);
  final alertReceiver = AlertReceiver(
    transceiverManager: transceiverManager,
    speechEngine: speechEngine,
  );
  final commPipeline = CommPipeline(
    audioRecorder: audioRecorder,
    vadEngine: vadEngine,
    speechEngine: speechEngine,
    transceiverManager: transceiverManager,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => TransceiverController(
            commPipeline: commPipeline,
            transceiverManager: transceiverManager,
            meshManager: meshManager,
            alertBroadcaster: alertBroadcaster,
            alertReceiver: alertReceiver,
            speechEngine: speechEngine,
            database: database,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsController(
            database: database,
            languagePackManager: languagePackManager,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => PeerController(
            meshManager: meshManager,
            transceiverManager: transceiverManager,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => HistoryController(
            database: database,
          ),
        ),
      ],
      child: const ITantraApp(),
    ),
  );
}

class ITantraApp extends StatelessWidget {
  const ITantraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iTantra Neural Transceiver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}
