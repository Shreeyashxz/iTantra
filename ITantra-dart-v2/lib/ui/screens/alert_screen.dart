import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../controllers/transceiver_controller.dart';

class AlertTemplate {
  final String id;
  final String title;
  final Map<String, String> translations;

  const AlertTemplate({
    required this.id,
    required this.title,
    required this.translations,
  });

  String getForLanguage(String lang) {
    return translations[lang] ?? translations['en'] ?? '';
  }
}

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  final TextEditingController _customAlertController = TextEditingController();
  String _selectedLang = 'hi';
  List<AlertTemplate> _templates = [];
  bool _isDndGranted = false;

  static const List<(String, String)> _languages = [
    ('hi', 'हिंदी'),
    ('en', 'English'),
    ('mr', 'मराठी'),
    ('gu', 'ગુજરાતી'),
    ('ta', 'தமிழ்'),
    ('te', 'తెలుగు'),
    ('kn', 'ಕನ್ನಡ'),
    ('ml', 'മലയാളം'),
    ('bn', 'বাংলা'),
    ('or', 'ଓଡ଼ିଆ'),
  ];

  @override
  void initState() {
    super.initState();
    _loadAlertTemplates();
    _checkDndStatus();
  }

  Future<void> _checkDndStatus() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.itantra/hardware_alert');
        final granted = await channel.invokeMethod<bool>('checkDndPermission') ?? false;
        if (mounted) {
          setState(() => _isDndGranted = granted);
        }
      } catch (_) {}
    }
  }

  Future<void> _requestDndPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.itantra/hardware_alert');
        await channel.invokeMethod('requestDndPermission');
        await Future.delayed(const Duration(seconds: 1));
        _checkDndStatus();
      } catch (_) {}
    }
  }

  Future<void> _loadAlertTemplates() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/alerts/alert_templates.json');
      final dynamic data = jsonDecode(jsonStr);
      if (data is Map && data['alerts'] is List) {
        final list = (data['alerts'] as List).map((item) {
          final map = item as Map<String, dynamic>;
          return AlertTemplate(
            id: map['id'] as String? ?? '',
            title: map['title'] as String? ?? 'Distress Alert',
            translations: Map<String, String>.from(map['translations'] as Map? ?? {}),
          );
        }).toList();

        if (mounted) {
          setState(() => _templates = list);
        }
      }
    } catch (e) {
      debugPrint('[AlertScreen] Error loading alert_templates.json: $e');
    }
  }

  @override
  void dispose() {
    _customAlertController.dispose();
    super.dispose();
  }

  void _dispatchAlert(BuildContext context, String text, String lang) {
    if (text.trim().isEmpty) return;

    final controller = context.read<TransceiverController>();
    controller.sendEmergencyAlert(text.trim(), languageCode: lang);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Distress alert broadcasted in ${lang.toUpperCase()}: "$text"'),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Distress Broadcast'),
        backgroundColor: theme.colorScheme.error,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Distress Priority Warning Card with DND Status
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.error.withAlpha(120)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 36,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Alerts transmit with highest priority, bypassing Do-Not-Disturb and playing at maximum hardware alarm volume on all receiving nodes.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!kIsWeb && Platform.isAndroid && !_isDndGranted) ...[
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _requestDndPermission,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(180),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.do_not_disturb_on_total_silence, size: 16, color: Colors.red),
                            SizedBox(width: 6),
                            Text(
                              'Tap to enable DND Override Permission for non-interruptible alerts',
                              style: TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Language Selector for Alert Templates
            Row(
              children: [
                Text(
                  'Template Language:',
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _languages.map((l) {
                        final isSel = _selectedLang == l.$1;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(l.$2),
                            selected: isSel,
                            onSelected: (_) => setState(() => _selectedLang = l.$1),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Text(
              'Quick Distress Templates (10 Indian Languages)',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Presets List
            Expanded(
              child: _templates.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _templates.length,
                      itemBuilder: (context, index) {
                        final t = _templates[index];
                        final text = t.getForLanguage(_selectedLang);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              Icons.emergency_share_rounded,
                              color: theme.colorScheme.error,
                            ),
                            title: Text(
                              t.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                text,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.send_rounded),
                              color: theme.colorScheme.error,
                              onPressed: () => _dispatchAlert(context, text, _selectedLang),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const Divider(),

            // Custom Alert Section
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customAlertController,
                    decoration: InputDecoration(
                      hintText: 'Type custom tactical emergency alert...',
                      prefixIcon: const Icon(Icons.edit_note_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    final txt = _customAlertController.text.trim();
                    if (txt.isNotEmpty) {
                      _dispatchAlert(context, txt, _selectedLang);
                      _customAlertController.clear();
                    }
                  },
                  icon: const Icon(Icons.campaign_rounded),
                  label: const Text('BROADCAST'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
