import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/transceiver_controller.dart';
import '../../speech/language_pack_manager.dart';
import '../widgets/pipeline_diagram.dart';

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
            // Live pipeline control center (force on/off + warnings + RAM pie)
            const PipelineDiagramCard(),
            const SizedBox(height: 16),
            // On-Demand Models Section
            Row(
              children: [
                Icon(Icons.psychology_rounded, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Neural Models (On-Demand Download)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
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
                      'On-device model files cached in private storage (<45MB base application footprint constraint).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '“Installed” = file on disk. Whether it is loaded in RAM is controlled in the Voice Pipeline card above.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // STT Engine Configuration & Precision Switch
                    Text(
                      'STT Model Precision (एकरूपता व परिशुद्धता)',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'INT8',
                            icon: const Icon(Icons.speed_rounded),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('INT8 (Fast)'),
                                if (settingsController.isSttReady)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(Icons.check_circle_rounded, size: 14, color: Colors.greenAccent),
                                  ),
                              ],
                            ),
                          ),
                          ButtonSegment(
                            value: 'FP32',
                            icon: const Icon(Icons.high_quality_rounded),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('FP32 (Accurate)'),
                                if (settingsController.isSttFp32Ready)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(Icons.check_circle_rounded, size: 14, color: Colors.greenAccent),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        selected: {settings.sttPrecision},
                        onSelectionChanged: (set) {
                          if (set.isNotEmpty) {
                            settingsController.updateSttPrecision(set.first);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      settings.sttPrecision == 'INT8'
                          ? '⚡ INT8 Quantized: ~120MB download, ultra-low CPU/RAM usage (~150ms latency).'
                          : '🎯 FP32 Full Precision: ~493MB download, maximum acoustic fidelity and noise robustness.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),

                    // STT INT8 Status Row
                    _ModelStatusRow(
                      title: 'IndicConformer INT8 Quantized (~120 MB)',
                      modelKey: 'stt',
                      isReady: settingsController.isSttReady,
                      downloadState: settingsController.downloadState,
                      onDownload: () => settingsController.downloadStt(),
                      onDelete: () => settingsController.deleteStt(),
                    ),
                    const SizedBox(height: 6),

                    // STT FP32 Status Row
                    _ModelStatusRow(
                      title: 'IndicConformer FP32 Full Precision (~493 MB)',
                      modelKey: 'stt_fp32',
                      isReady: settingsController.isSttFp32Ready,
                      downloadState: settingsController.downloadState,
                      onDownload: () => settingsController.downloadSttFp32(),
                      onDelete: () => settingsController.deleteSttFp32(),
                    ),
                    const Divider(height: 16),

                    // MT Model Downloads (IndicTrans2 INT8 Quantized)
                    Text(
                      'Machine Translation (AI4Bharat IndicTrans2 INT8)',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sovereign on-device neural Seq2Seq translation using quantized INT8 ONNX models with zero cloud dependency.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),

                    // MT Indic-to-Indic 320M INT8 Status
                    _ModelStatusRow(
                      title: 'IndicTrans2 Indic ➔ Indic (320M INT8 ONNX)',
                      subtitle: 'hari31416/indictrans2-indic-indic-dist-320M-ONNX-int8 (~330 MB)',
                      modelKey: 'mt_indic_indic',
                      isReady: settingsController.isMtIndicIndicReady,
                      downloadState: settingsController.downloadState,
                      onDownload: () => settingsController.downloadMtIndicIndic(),
                      onDelete: () => settingsController.deleteMtIndicIndic(),
                    ),
                    const SizedBox(height: 8),

                    // MT Indic-to-English 200M INT8 Status
                    _ModelStatusRow(
                      title: 'IndicTrans2 Indic ➔ English (200M INT8 ONNX)',
                      subtitle: 'hari31416/indictrans2-indic-en-dist-200M-ONNX-int8 (~230 MB)',
                      modelKey: 'mt_indic_en',
                      isReady: settingsController.isMtIndicEnReady,
                      downloadState: settingsController.downloadState,
                      onDownload: () => settingsController.downloadMtIndicEn(),
                      onDelete: () => settingsController.deleteMtIndicEn(),
                    ),
                    const Divider(height: 16),

                    // AI4Bharat Universal TTS (Rasa-13)
                    _ModelStatusRow(
                      title: 'Universal TTS (AI4Bharat Rasa-13 VITS — All 13 Languages, ~123 MB)',
                      modelKey: 'rasa13',
                      isReady: settingsController.isRasa13Ready,
                      downloadState: settingsController.downloadState,
                      onDownload: () => settingsController.downloadRasa13(),
                      onDelete: () => settingsController.deleteRasa13(),
                    ),
                    const SizedBox(height: 6),

                    // AI4Bharat IndicXlit Neural Transliteration
                    // NOTE: the ONNX bundle is not published upstream yet — the
                    // toggle works offline via rule-based fallback; download needs
                    // scripts/export_indicxlit_onnx.py + hosting (see code comment).
                    _ModelStatusRow(
                      title: 'Neural Transliteration (AI4Bharat IndicXlit / Aksharantar, ~35 MB)',
                      subtitle: 'Optional — toggle works offline without this (fallback active)',
                      modelKey: 'indicxlit',
                      isReady: settingsController.isIndicXlitReady,
                      downloadState: settingsController.downloadState,
                      onDownload: () => settingsController.downloadIndicXlit(),
                      onDelete: () => settingsController.deleteIndicXlit(),
                    ),
                    const SizedBox(height: 6),

                    // AI4Bharat IndicLID-FastText Language Identification (261MB — Wi-Fi recommended)
                    _ModelStatusRow(
                      title: 'Language Identification (AI4Bharat IndicLID-FastText, 261 MB)',
                      modelKey: 'lid',
                      isReady: settingsController.isLidReady,
                      downloadState: settingsController.downloadState,
                      onDownload: () => settingsController.downloadLid(),
                      onDelete: () => settingsController.deleteLid(),
                    ),
                    const Divider(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'TTS Voices — 10 Languages (Meta MMS / Indic)',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton.icon(
                              onPressed: () => settingsController.downloadAllLanguages(),
                              icon: const Icon(Icons.download_for_offline_rounded, size: 18),
                              label: const Text('Download All'),
                            ),
                            TextButton.icon(
                              onPressed: () => settingsController.deleteAllModels(),
                              icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.redAccent),
                              label: const Text('Delete All', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 10 Language TTS Rows — each with inline progress bar.
                    // NOTE: Rasa-13 is one universal 13-language voice. When it is
                    // installed, every language row correctly shows Installed
                    // (covered by Rasa-13, no per-language file needed).
                    ...settingsController.languages.map((lang) {
                      final isReady = settings.ttsEngineType == 'META_MMS'
                          ? settingsController.isMmsReady(lang.code)
                          : settingsController.isTtsReady(lang.code);
                      final coveredByRasa = settings.ttsEngineType != 'META_MMS' &&
                          settingsController.isRasa13Ready;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _ModelStatusRow(
                          title: '${lang.nativeName} (${lang.englishName})',
                          subtitle: coveredByRasa ? 'Covered by universal Rasa-13 voice' : null,
                          modelKey: 'tts_${lang.code}',
                          isReady: isReady,
                          downloadState: settingsController.downloadState,
                          onDownload: () => settingsController.downloadTts(lang.code),
                          onDelete: () => settingsController.deleteTts(lang.code),
                        ),
                      );
                    }),
                    const SizedBox(height: 14),

                    // Global status message (completed / error only — no progress bar here)
                    if (settingsController.downloadState is DownloadStateCompleted) ...[
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
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Primary Language Selector
            Row(
              children: [
                Icon(Icons.translate_rounded, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Speech Engine Calibration',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
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
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Audio & Transceiver Calibration',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active Neural TTS Engine (स्पीच इंजन चयन)',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'AI4BHARAT_RASA',
                            icon: const Icon(Icons.hub_rounded),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('AI4Bharat Rasa-13'),
                                if (settingsController.isRasa13Ready)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(Icons.check_circle_rounded, size: 14, color: Colors.greenAccent),
                                  ),
                              ],
                            ),
                          ),
                          const ButtonSegment(
                            value: 'META_MMS',
                            icon: Icon(Icons.language_rounded),
                            label: Text('Meta MMS VITS'),
                          ),
                          const ButtonSegment(
                            value: 'OS_NATIVE',
                            icon: Icon(Icons.phone_android_rounded),
                            label: Text('OS Native'),
                          ),
                        ],
                        selected: {settings.ttsEngineType},
                        onSelectionChanged: (set) {
                          if (set.isNotEmpty) {
                            settingsController.updateTtsEngineType(set.first);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      settings.ttsEngineType == 'AI4BHARAT_RASA'
                          ? '🇮🇳 Sovereign Indian Stack: 1 single ~123MB pack covers Indic languages with multi-speaker support.'
                          : settings.ttsEngineType == 'OS_NATIVE'
                              ? '📱 Platform Native Engine: Zero download size, zero RAM. Uses built-in Android TextToSpeech or Windows OneCore voices.'
                              : '🌐 Meta Massively Multilingual: Lightweight single-language VITS packs tailored per regional language (covers all 10 SIH languages).',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (settings.ttsEngineType == 'AI4BHARAT_RASA') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withAlpha(100)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Warning: AI4Bharat Rasa-13 does not support Gujarati (gu), Odia (or), or English (en). For these languages, iTantra automatically falls back to Meta MMS-TTS or OS Native.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.amber.shade200,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    Text(
                      'Voice Gender (आवाज का प्रकार)',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'FEMALE',
                            icon: Icon(Icons.female_rounded),
                            label: Text('Female (स्त्री)'),
                          ),
                          ButtonSegment(
                            value: 'MALE',
                            icon: Icon(Icons.male_rounded),
                            label: Text('Male (पुरुष)'),
                          ),
                        ],
                        selected: {settings.ttsGender},
                        onSelectionChanged: (set) {
                          if (set.isNotEmpty) {
                            settingsController.updateTtsGender(set.first);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

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

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'VAD Voice Sensitivity: ${(settings.vadSensitivity * 100).toInt()}%',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          settings.vadSensitivity >= 0.7
                              ? 'High (Soft Voice)'
                              : settings.vadSensitivity <= 0.3
                                  ? 'Low (Noisy Room)'
                                  : 'Balanced',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: settings.vadSensitivity,
                      min: 0.1,
                      max: 1.0,
                      divisions: 9,
                      label: '${(settings.vadSensitivity * 100).toInt()}%',
                      onChanged: (val) => settingsController.updateVadSensitivity(val),
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
                    const Divider(height: 24),
                    Text(
                      'Script Normalization & Transliteration Engine',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Controls how cross-script Indic text and Latin phonetics are aligned between sender and receiver.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RadioGroup<String>(
                      groupValue: settings.normalizerMode,
                      onChanged: (val) {
                        if (val != null) settingsController.updateNormalizerMode(val);
                      },
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            title: const Text('Advanced Phonological Matrix (Recommended)'),
                            subtitle: const Text('Linguistically authentic phoneme mapping across all 10 languages, proper Dravidian consonant collapsing (Tamil/Malayalam), and Neural IndicXlit ready.'),
                            value: 'ADVANCED',
                            contentPadding: EdgeInsets.zero,
                          ),
                          RadioListTile<String>(
                            title: const Text('Legacy Rule-Based Engine'),
                            subtitle: const Text('Original ISCII Unicode block offset shift heuristic and basic lexicon.'),
                            value: 'LEGACY_RULE_BASED',
                            contentPadding: EdgeInsets.zero,
                          ),
                          RadioListTile<String>(
                            title: const Text('Neural IndicXlit (AI4Bharat Aksharantar)'),
                            subtitle: const Text('Transformer-based neural seq2seq transliteration model (~35 MB ONNX) for contextual loanwords and script prediction.'),
                            value: 'NEURAL_INDIC_XLIT',
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 6),
                      child: _ModelStatusRow(
                        title: 'IndicXlit Weights (~35 MB)',
                        modelKey: 'indicxlit',
                        isReady: settingsController.isIndicXlitReady,
                        downloadState: settingsController.downloadState,
                        onDownload: () => settingsController.downloadIndicXlit(),
                        onDelete: () => settingsController.deleteIndicXlit(),
                      ),
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
                    Text('• STT Engine: AI4Bharat IndicConformer (INT8 quantized)',
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
  final String? subtitle;
  final String modelKey;
  final bool isReady;
  final DownloadState downloadState;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _ModelStatusRow({
    required this.title,
    this.subtitle,
    required this.modelKey,
    required this.isReady,
    required this.downloadState,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Check if THIS model is the one currently downloading
    final isThisDownloading = downloadState is DownloadStateDownloading &&
        (downloadState as DownloadStateDownloading).modelKey == modelKey;
    final downloadPercent = isThisDownloading
        ? (downloadState as DownloadStateDownloading).progressPercent
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Status icon — fixed width for alignment
            SizedBox(
              width: 22,
              child: isThisDownloading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : Icon(
                      isReady
                          ? Icons.check_circle_rounded
                          : Icons.download_rounded,
                      size: 18,
                      color: isReady
                          ? const Color(0xFF00E676)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
            ),
            const SizedBox(width: 10),

            // Title + status text — expands to fill
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withAlpha(200),
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    isThisDownloading
                        ? '⬇ Downloading… $downloadPercent%'
                        : isReady
                            ? '✅ Installed & Ready'
                            : '⚠️ Not Installed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isThisDownloading
                          ? theme.colorScheme.primary
                          : isReady
                              ? const Color(0xFF00E676)
                              : theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Action button
            if (isThisDownloading)
              const SizedBox(width: 48) // placeholder to keep alignment while downloading
            else if (!isReady)
              ElevatedButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              )
            else
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete Model',
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
              ),
          ],
        ),

        // Inline progress bar below this row
        if (isThisDownloading) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: downloadPercent / 100.0,
                minHeight: 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
