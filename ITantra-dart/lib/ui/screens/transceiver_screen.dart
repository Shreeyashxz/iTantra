import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/transceiver_controller.dart';
import '../widgets/message_bubble.dart';
import 'alert_screen.dart';
import 'peer_discovery_screen.dart';

class TransceiverScreen extends StatefulWidget {
  const TransceiverScreen({super.key});

  @override
  State<TransceiverScreen> createState() => _TransceiverScreenState();
}

class _TransceiverScreenState extends State<TransceiverScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const List<(String, String)> _languages = [
    ('hi', 'हिंदी'),
    ('en', 'English'),
    ('gu', 'ગુજરાતી'),
    ('mr', 'मराठी'),
    ('kn', 'ಕನ್ನಡ'),
    ('ml', 'മലയാളം'),
    ('ta', 'தமிழ்'),
    ('te', 'తెలుగు'),
    ('or', 'ଓଡ଼ିଆ'),
    ('bn', 'বাংলা'),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.16).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<TransceiverController>();

    if (controller.isTransmitting && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!controller.isTransmitting && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }

    final isConnected = controller.connectionStatus.contains('Connected');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('iTantra Transceiver'),
            Text(
              'Link: ${controller.connectionStatus}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isConnected ? const Color(0xFF00E676) : theme.colorScheme.onSurfaceVariant,
                fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isConnected ? Icons.wifi_tethering_rounded : Icons.wifi_find_rounded,
              color: isConnected ? const Color(0xFF00E676) : null,
            ),
            tooltip: 'Wi-Fi Mesh Discovery',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PeerDiscoveryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded),
            color: theme.colorScheme.error,
            tooltip: 'Emergency Alert',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AlertScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // No Mesh Peer Warning Banner
          if (!isConnected)
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PeerDiscoveryScreen()),
              ),
              child: Container(
                width: double.infinity,
                color: theme.colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No peer linked — Tap to discover & pair over Wi-Fi Mesh',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 12, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          // Active Distress Alert Banner
          if (controller.activeAlert != null)
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.error),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_rounded, color: theme.colorScheme.error, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMERGENCY ALERT RECEIVED',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          controller.activeAlert!.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => controller.dismissAlert(),
                    child: Text(
                      'DISMISS',
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Horizontal Language Selector Chips
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _languages.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final (code, name) = _languages[index];
                final isSelected = controller.selectedLanguage == code;

                return ChoiceChip(
                  label: Text(name),
                  selected: isSelected,
                  onSelected: (_) => controller.setLanguage(code),
                  selectedColor: theme.colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),

          // Message & Transcript Stream
          Expanded(
            child: controller.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.speaker_phone_rounded,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No transmissions yet.\nHold Push-To-Talk to speak.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: controller.messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: controller.messages[index]);
                    },
                  ),
          ),

          // Quick Text Transmission bar (Quiet / Direct mode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Quiet mode utterance...',
                      hintStyle: theme.textTheme.bodySmall,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        controller.sendUtterance(val);
                        _textController.clear();
                        _scrollToBottom();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send_rounded, size: 18),
                  onPressed: () {
                    if (_textController.text.trim().isNotEmpty) {
                      controller.sendUtterance(_textController.text);
                      _textController.clear();
                      _scrollToBottom();
                    }
                  },
                ),
              ],
            ),
          ),

          // Transmitting Bitrate Status
          AnimatedOpacity(
            opacity: controller.isTransmitting ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Transmitting semantic voice payload (~160 bps)...',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Large Push-To-Talk Button
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 28),
            child: GestureDetector(
              onTapDown: (_) => controller.onPttPressed(),
              onTapUp: (_) => controller.onPttReleased(),
              onTapCancel: () => controller.onPttReleased(),
              child: ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 124,
                  height: 124,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: controller.isTransmitting
                          ? [
                              theme.colorScheme.error,
                              const Color(0xFFB71C1C),
                            ]
                          : [
                              theme.colorScheme.primary,
                              const Color(0xFF0D47A1),
                            ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (controller.isTransmitting
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary)
                            .withAlpha(controller.isTransmitting ? 150 : 80),
                        blurRadius: controller.isTransmitting ? 24 : 14,
                        spreadRadius: controller.isTransmitting ? 4 : 0,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        controller.isTransmitting
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        controller.isTransmitting ? 'RECORDING' : 'HOLD PTT',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
