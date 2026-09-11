import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/transceiver_controller.dart';
import 'home_screen.dart';

class LanguageSetupScreen extends StatefulWidget {
  const LanguageSetupScreen({super.key});

  @override
  State<LanguageSetupScreen> createState() => _LanguageSetupScreenState();
}

class _LanguageSetupScreenState extends State<LanguageSetupScreen> {
  String _primaryLang = 'hi';
  String _pttMode = 'HOLD';
  bool _downloadOnFinish = true;
  bool _isSaving = false;

  static const List<(String, String, String)> _languages = [
    ('hi', 'हिंदी', 'Hindi'),
    ('en', 'English', 'English'),
    ('mr', 'मराठी', 'Marathi'),
    ('gu', 'ગુજરાતી', 'Gujarati'),
    ('ta', 'தமிழ்', 'Tamil'),
    ('te', 'తెలుగు', 'Telugu'),
    ('kn', 'ಕನ್ನಡ', 'Kannada'),
    ('ml', 'മലയാളം', 'Malayalam'),
    ('bn', 'বাংলা', 'Bengali'),
    ('or', 'ଓଡ଼ିଆ', 'Odia'),
  ];

  Future<void> _completeSetup() async {
    setState(() => _isSaving = true);
    final settingsCtrl = context.read<SettingsController>();
    final transceiverCtrl = context.read<TransceiverController>();

    try {
      await settingsCtrl.updatePreferredLanguage(_primaryLang);
      await settingsCtrl.updatePttMode(_pttMode);
      transceiverCtrl.setLanguage(_primaryLang);

      final currentPacks = settingsCtrl.settings.installedLanguagePacks;
      if (!currentPacks.contains('SETUP_DONE')) {
        final newPacks = currentPacks.isEmpty ? 'SETUP_DONE' : '$currentPacks,SETUP_DONE';
        await settingsCtrl.updateInstalledPacks(newPacks);
      }

      if (_downloadOnFinish) {
        // Kick off background model download if not already cached
        if (!settingsCtrl.isSttReady) {
          settingsCtrl.downloadStt();
        }
      }
    } catch (e) {
      debugPrint('[LanguageSetup] Error saving initial configuration: $e');
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Initial Device Calibration'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Welcome Card
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.satellite_alt_rounded, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'iTantra Neural Transceiver',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Welcome to iTantra. Configure your native language preferences for low-bitrate semantic compression (~160 bps voice over Wi-Fi Direct / Mesh links).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Select Primary Indian Language',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'This language will be prioritized for speech recognition and tactical distress alerts.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _languages.map((lang) {
                final isSelected = _primaryLang == lang.$1;
                return ChoiceChip(
                  label: Text('${lang.$2} (${lang.$3})'),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _primaryLang = lang.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            Text(
              'Push-To-Talk (PTT) Interaction Mode',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            RadioGroup<String>(
              groupValue: _pttMode,
              onChanged: (val) => setState(() => _pttMode = val!),
              child: Column(
                children: const [
                  RadioListTile<String>(
                    title: Text('Hold-To-Talk (Tactical Walkie-Talkie)'),
                    subtitle: Text('Hold button to speak, release to immediately compress and transmit.'),
                    value: 'HOLD',
                  ),
                  RadioListTile<String>(
                    title: Text('Tap-To-Toggle (Hands-Free Dictation)'),
                    subtitle: Text('Tap once to start speaking, tap again or pause to transmit.'),
                    value: 'TOGGLE',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            CheckboxListTile(
              title: const Text('Download Essential Neural STT Weights'),
              subtitle: const Text('Automatically caches IndicConformer INT8 weights in local app storage.'),
              value: _downloadOnFinish,
              onChanged: (val) => setState(() => _downloadOnFinish = val ?? true),
            ),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _isSaving ? null : _completeSetup,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'START USING iTANTRA',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
