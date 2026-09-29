import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'alerts/alert_broadcaster.dart';
import 'speech/indic_trans_engine.dart';
import 'speech/neural_mt_engine.dart';
import 'utils/app_permissions.dart';
import 'alerts/alert_receiver.dart';
import 'controllers/history_controller.dart';
import 'controllers/peer_controller.dart';
import 'controllers/settings_controller.dart';
import 'controllers/transceiver_controller.dart';
import 'data/app_database.dart';
import 'network/transceiver_manager.dart';
import 'network/wifi_direct_p2p_service.dart';
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

  try {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  } catch (e) {
    debugPrint('Orientation lock not supported: $e');
  }

  // Custom ErrorWidget to ensure any release-mode rendering error displays readable info instead of a blank screen
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF0A0E17),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'Initialization notice: ${details.exceptionAsString()}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize sherpa-onnx native bindings:
  // On Windows: pass exeDir so onnxruntime and sherpa-onnx DLLs are loaded from the runner directory.
  // On Android: pre-load onnxruntime if needed, then call sherpa.initBindings() without arguments so Android loads .so from APK jniLibs.
  try {
    if (!kIsWeb && Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final ortPath = p.join(exeDir, 'onnxruntime.dll');
      if (File(ortPath).existsSync()) {
        try {
          DynamicLibrary.open(ortPath);
          debugPrint('[Init] Bundled onnxruntime.dll pre-loaded successfully: $ortPath');
        } catch (e) {
          debugPrint('[Init] Notice pre-loading onnxruntime.dll: $e');
        }
      }
      sherpa.initBindings(exeDir);
    } else if (!kIsWeb) {
      if (Platform.isAndroid) {
        try {
          DynamicLibrary.open('libonnxruntime.so');
        } catch (_) {}
      }
      sherpa.initBindings();
    }
  } catch (e) {
    debugPrint('[Init] sherpa-onnx initBindings notice: $e');
  }

  await IndicTransEngine.loadLexicon();

  // Pre-request mesh runtime permissions so discovery doesn't silently fail.
  // Mic is requested lazily on first PTT (AppPermissions.ensureMicrophone).
  try {
    await AppPermissions.ensureMeshPermissions();
    await AppPermissions.ensureNotifications();
  } catch (_) {}

  // Core singletons (matching Hilt AppModule / SpeechModule / TransportModule / DatabaseModule)
  final database = AppDatabase.instance;
  final languagePackManager = LanguagePackManager();
  await languagePackManager.syncExistingModels();
  final audioRecorder = AudioRecorderService();
  final vadEngine = SileroVadEngine();
  final speechEngine = SherpaOnnxSpeechEngine(languagePackManager: languagePackManager);
  final transceiverManager = TransceiverManager();
  final meshManager = WifiMeshManager(transceiverManager: transceiverManager);
  final p2pService = WifiDirectP2pService(transceiverManager: transceiverManager);
  final alertBroadcaster = AlertBroadcaster(transceiverManager: transceiverManager);
  final alertReceiver = AlertReceiver(
    transceiverManager: transceiverManager,
    speechEngine: speechEngine,
    database: database,
  );
  final commPipeline = CommPipeline(
    audioRecorder: audioRecorder,
    vadEngine: vadEngine,
    speechEngine: speechEngine,
    transceiverManager: transceiverManager,
  );

  // Keep a strong reference — a discarded AppLifecycleListener may be GC'd
  // and background mic/sockets would keep running on Android.
  final lifecycleListener = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.detached) {
        // Sync teardown; callbacks can't await — fire-and-forget safely.
        AppDatabase.instance.close();
        NeuralMtEngine.instance.unload();
        speechEngine.release();
        transceiverManager.dispose();
        meshManager.dispose();
        p2pService.dispose();
        alertReceiver.dispose();
        commPipeline.dispose();
        audioRecorder.dispose();
        vadEngine.release();
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        // Stop mic + timers when backgrounded (privacy + battery).
        commPipeline.stopVadAutoMode();
        audioRecorder.stopRecording();
        vadEngine.stopVad();
      }
    },
  );
  // ignore: unused_local_variable — retained for lifecycle duration via closure.
  debugPrint('[Init] Lifecycle listener attached: $lifecycleListener');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          lazy: false,
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
            speechEngine: speechEngine,
          ),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => PeerController(
            meshManager: meshManager,
            transceiverManager: transceiverManager,
            p2pService: p2pService,
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
