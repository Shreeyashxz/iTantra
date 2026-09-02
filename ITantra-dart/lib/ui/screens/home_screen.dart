import 'package:flutter/material.dart';
import 'alert_screen.dart';
import 'history_screen.dart';
import 'peer_discovery_screen.dart';
import 'settings_screen.dart';
import 'transceiver_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('iTantra Dashboard'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mission Info Card
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ISRO • SIH 26173',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Neural Transceiver for Low-Bitrate Links',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Multilingual voice compression (~160 bps) via local on-device VAD, STT, and TTS across 10 Indian languages.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Action Tiles
            _ActionTile(
              title: 'Push-To-Talk Transceiver',
              subtitle: 'Hold-to-talk semantic voice streaming',
              icon: Icons.mic_rounded,
              color: theme.colorScheme.primary,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TransceiverScreen()),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              title: 'Emergency Distress Alert',
              subtitle: 'Max volume, non-interruptible alert broadcast',
              icon: Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AlertScreen()),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              title: 'Peer Discovery & Mesh',
              subtitle: 'Connect devices over Wi-Fi LAN / Hotspot Mesh',
              icon: Icons.wifi_tethering_rounded,
              color: theme.colorScheme.secondary,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PeerDiscoveryScreen()),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              title: 'Transmission History',
              subtitle: 'View and search offline message logs',
              icon: Icons.history_rounded,
              color: const Color(0xFFAB47BC),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              title: 'Settings & Calibration',
              subtitle: 'Language selection, TTS speed & models',
              icon: Icons.tune_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withAlpha(35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
