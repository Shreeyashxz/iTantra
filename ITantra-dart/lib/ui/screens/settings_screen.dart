import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/transceiver_controller.dart';
import '../../speech/language_pack_manager.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<(String, String)> _languages = [
    ('hi', 'Hindi (हिंदी)'),
    ('en', 'English'),
    ('gu', 'Gujarati (ગુજરાતી)'),
    ('mr', 'Marathi (मराठी)'),
    ('kn', 'Kannada (ಕನ್ನಡ)'),
    ('ml', 'Malayalam (മലയാളം)'),
    ('ta', 'Tamil (தமிழ்)'),
    ('te', 'Telugu (తెలుగు)'),
    ('or', 'Odia (ଓଡ଼ିଆ)'),
    ('bn', 'Bengali (বাংলা)'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsController = context.watch<SettingsController>();
    final transceiverController = context.watch<TransceiverController>();
    final settings = settingsController.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Calibration'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // On-Demand Models Section
            Text(
              'Neural Models (On-Demand Download)',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'On-device models are cached in private storage (<45MB base application footprint constraint).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // STT Status
                    _ModelStatusRow(
                      title: 'STT Engine (Zipformer INT8)',
                      isReady: settingsController.isSttReady,
                      onDownload: () => settingsController.downloadStt(),
                    ),
                    const Divider(height: 20),

                    // Hindi TTS Status
                    _ModelStatusRow(
                      title: 'TTS Voice — Hindi (VITS)',
                      isReady: settingsController.isHiTtsReady,
                      onDownload: () => settingsController.downloadTts('hi'),
                    ),
                    const Divider(height: 20),

                    // English TTS Status
                    _ModelStatusRow(
                      title: 'TTS Voice — English (VITS)',
                      isReady: settingsController.isEnTtsReady,
                      onDownload: () => settingsController.downloadTts('en'),
                    ),
                    const SizedBox(height: 14),

                    // Download state indicator
                    if (settingsController.downloadState is DownloadStateDownloading) ...[
                      Builder(builder: (ctx) {
                        final state =
                            settingsController.downloadState as DownloadStateDownloading;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Downloading ${state.item}: ${state.progressPercent}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: state.progressPercent / 100.0,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      }),
                    ] else if (settingsController.downloadState is DownloadStateCompleted) ...[
                      Builder(builder: (ctx) {
                        final state =
                            settingsController.downloadState as DownloadStateCompleted;
                        return Text(
                          '🎉 ${state.message}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF00E676),
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }),
                    ] else if (settingsController.downloadState is DownloadStateError) ...[
                      Builder(builder: (ctx) {
                        final state =
                            settingsController.downloadState as DownloadStateError;
                        return Text(
                          '❌ ${state.message}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        );
                      }),
                    ] else if (!settingsController.isSttReady ||
                        !settingsController.isHiTtsReady ||
                        !settingsController.isEnTtsReady) ...[
                      OutlinedButton.icon(
                        onPressed: () => settingsController.downloadAllEssentials(),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download All Essential Models'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Primary Language Selector
            Text(
              'Speech Engine Calibration',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Primary Language: ${transceiverController.selectedLanguage.toUpperCase()}',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ..._languages.map((lang) {
                      final (code, label) = lang;
                      final isSelected = transceiverController.selectedLanguage == code;
                      return ListTile(
                        title: Text(label, style: theme.textTheme.bodyMedium),
                        trailing: Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        onTap: () => transceiverController.setLanguage(code),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Audio & Playback Controls
            Text(
              'Audio & Transceiver Calibration',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TTS Playback Speed: ${settings.ttsSpeed.toStringAsFixed(1)}x',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Slider(
                      value: settings.ttsSpeed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 6,
                      label: '${settings.ttsSpeed.toStringAsFixed(1)}x',
                      onChanged: (val) => settingsController.updateTtsSpeed(val),
                    ),
                    const SizedBox(height: 10),

                    SwitchListTile(
                      title: const Text('Auto-Play Received Voice'),
                      subtitle: const Text('Synthesize audio automatically when packet arrives'),
                      value: settings.autoPlayAudio,
                      onChanged: (val) => settingsController.updateAutoPlayAudio(val),
                      contentPadding: EdgeInsets.zero,
                    ),

                    SwitchListTile(
                      title: const Text('Hold-to-Talk Mode'),
                      subtitle: const Text('Hold PTT button down to transmit speech'),
                      value: settings.pttMode == 'HOLD',
                      onChanged: (val) =>
                          settingsController.updatePttMode(val ? 'HOLD' : 'TOGGLE'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Footprint Summary
            Text(
              'On-Device Footprint & Specifications',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• VAD Engine: Silero VAD (~629 KB on disk)',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text('• STT Engine: Sherpa-ONNX Zipformer (INT8 quantized)',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text('• TTS Engine: Piper / VITS Multilingual Checkpoints',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text('• Peak RAM Target: < 420 MB (ISRO Constraint < 1 GB)',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text('• Bitrate: ~160 bps Semantic Compression (vs 16 kbps audio)',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelStatusRow extends StatelessWidget {
  final String title;
  final bool isReady;
  final VoidCallback onDownload;

  const _ModelStatusRow({
    required this.title,
    required this.isReady,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                isReady ? '✅ Installed & Ready' : '⚠️ Not Installed',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isReady ? const Color(0xFF00E676) : theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (!isReady)
          ElevatedButton(
            onPressed: onDownload,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('Download'),
          ),
      ],
    );
  }
}
