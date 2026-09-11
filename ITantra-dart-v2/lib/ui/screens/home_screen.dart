import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/settings_controller.dart';
import '../theme/app_theme.dart';
import 'alert_screen.dart';
import 'history_screen.dart';
import 'model_test_lab_screen.dart';
import 'peer_discovery_screen.dart';
import 'settings_screen.dart';
import 'transceiver_screen.dart';
import 'walkie_talkie_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    SettingsController? settings;
    try {
      settings = context.watch<SettingsController>();
    } catch (_) {
      settings = null;
    }

    // If ELI-5 UI mode is active (default for v2), show the clean Walkie-Talkie screen!
    if (settings != null && settings.isEli5Ui) {
      return WalkieTalkieScreen(
        onSwitchToClassicUi: () => settings?.updateUiMode('CLASSIC'),
      );
    }

    // Otherwise, show Classic Multi-Tab Dashboard
    return Scaffold(
      appBar: AppBar(
        title: const Text('iTantra Dashboard (Classic)'),
        actions: [
          TextButton.icon(
            onPressed: () => settings?.updateUiMode('ELI5'),
            icon: const Icon(Icons.radio_rounded, size: 16, color: Color(0xFF00E676)),
            label: const Text(
              'Switch to ELI-5 UI',
              style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner to toggle back to ELI-5 Walkie-Talkie
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E676).withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.radio_rounded, color: Color(0xFF00E676), size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ELI-5 Tactical UI Available',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        ),
                        Text(
                          'Minimalist walkie-talkie with instant auto-translating speech.',
                          style: TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => settings?.updateUiMode('ELI5'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    child: const Text('USE ELI-5 UI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            ),
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

            // Action Tiles with Staggered Entrance and original Card palette
            _ActionTile(
              index: 0,
              title: 'Push-To-Talk Transceiver',
              subtitle: 'Hold-to-talk semantic voice streaming',
              icon: Icons.mic_rounded,
              heroTag: 'hero_transceiver',
              color: theme.colorScheme.primary,
              onTap: () => Navigator.of(context).push(
                AppTheme.pageTransition(const TransceiverScreen()),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              index: 1,
              title: 'Emergency Distress Alert',
              subtitle: 'Max volume, non-interruptible alert broadcast',
              icon: Icons.warning_amber_rounded,
              heroTag: 'hero_alert',
              color: theme.colorScheme.error,
              onTap: () => Navigator.of(context).push(
                AppTheme.pageTransition(const AlertScreen()),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              index: 2,
              title: 'Peer Discovery & Mesh',
              subtitle: 'Connect devices over Wi-Fi LAN / Hotspot Mesh',
              icon: Icons.wifi_tethering_rounded,
              heroTag: 'hero_mesh',
              color: theme.colorScheme.secondary,
              onTap: () => Navigator.of(context).push(
                AppTheme.pageTransition(const PeerDiscoveryScreen()),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              index: 3,
              title: 'Transmission History',
              subtitle: 'View and search offline message logs',
              icon: Icons.history_rounded,
              heroTag: 'hero_history',
              color: const Color(0xFFAB47BC),
              onTap: () => Navigator.of(context).push(
                AppTheme.pageTransition(const HistoryScreen()),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              index: 4,
              title: 'Settings & Calibration',
              subtitle: 'Language selection, TTS speed & models',
              icon: Icons.tune_rounded,
              heroTag: 'hero_settings',
              color: theme.colorScheme.onSurfaceVariant,
              onTap: () => Navigator.of(context).push(
                AppTheme.pageTransition(const SettingsScreen()),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              index: 5,
              title: 'Neural Speech & Dev Diagnostics',
              subtitle: 'Expert diagnostics suite for all 7 neural pipelines (STT, MT, TTS)',
              icon: Icons.developer_mode_rounded,
              heroTag: 'hero_diagnostics',
              color: const Color(0xFF00E676),
              onTap: () => Navigator.of(context).push(
                AppTheme.pageTransition(const ModelTestLabScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatefulWidget {
  final int index;
  final String title;
  final String subtitle;
  final IconData icon;
  final String heroTag;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.heroTag,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(curved);

    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Card(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Hero(
                    tag: widget.heroTag,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: widget.color.withAlpha(35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon, color: widget.color, size: 26),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
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
        ),
      ),
    );
  }
}
