import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/transceiver_controller.dart';

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  final TextEditingController _customAlertController = TextEditingController();
  String? _sentMessageFeedback;

  static const List<String> _presetAlerts = [
    'Emergency! Immediate assistance required.',
    'Medical emergency! Send doctor or ambulance.',
    'Distress alert! Lost signal / navigation failure.',
    'Severe weather alert! Evacuate immediately.',
    'Fire hazard detected! Need urgent backup.',
  ];

  @override
  void dispose() {
    _customAlertController.dispose();
    super.dispose();
  }

  void _dispatchAlert(BuildContext context, String text) {
    if (text.trim().isEmpty) return;

    final controller = context.read<TransceiverController>();
    controller.sendEmergencyAlert(text.trim());

    setState(() {
      _sentMessageFeedback = text.trim();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Distress alert broadcasted: "$text"'),
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
            // Distress Priority Warning Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.error.withAlpha(120)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 36,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Alerts transmit with maximum priority and trigger high-volume voice synthesis & haptic alarms on all nearby nodes.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Quick Distress Templates',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Presets List
            Expanded(
              child: ListView.separated(
                itemCount: _presetAlerts.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final alert = _presetAlerts[index];
                  return Card(
                    elevation: 1,
                    child: ListTile(
                      title: Text(alert, style: theme.textTheme.bodyMedium),
                      trailing: Icon(
                        Icons.send_rounded,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      onTap: () => _dispatchAlert(context, alert),
                    ),
                  );
                },
              ),
            ),

            if (_sentMessageFeedback != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Last Broadcast: "$_sentMessageFeedback"',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // Custom Alert Section
            TextField(
              controller: _customAlertController,
              decoration: InputDecoration(
                labelText: 'Custom Emergency Message',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),

            ElevatedButton.icon(
              onPressed: () {
                if (_customAlertController.text.trim().isNotEmpty) {
                  _dispatchAlert(context, _customAlertController.text);
                  _customAlertController.clear();
                }
              },
              icon: const Icon(Icons.emergency_rounded),
              label: const Text('BROADCAST CUSTOM ALERT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
