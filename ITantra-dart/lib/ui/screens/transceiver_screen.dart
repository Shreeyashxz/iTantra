import 'dart:math' as math;
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
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _waveController;
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
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
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

    if (controller.isTransmitting) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
      if (!_waveController.isAnimating) _waveController.repeat();
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
      if (_waveController.isAnimating) {
        _waveController.stop();
        _waveController.reset();
      }
    }

    final isConnected = controller.connectionStatus.contains('Connected');

    // Show PTT error as SnackBar if present
    if (controller.pttError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.pttError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 4),
              backgroundColor: const Color(0xFF7F1D1D),
              content: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      controller.pttError!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
          controller.clearPttError();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('iTantra Transceiver'),
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Link: ${controller.connectionStatus}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isConnected ? const Color(0xFF00E676) : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (controller.linkRttMs != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green, width: 0.8),
                    ),
                    child: Text(
                      '⏱️ ${controller.linkRttMs}ms • ~160 bps',
                      style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bolt_rounded, color: Colors.amberAccent),
            tooltip: 'Run JIT Pipeline (STT ➔ MT ➔ Mesh ➔ TTS)',
            onPressed: () {
              controller.triggerJitPipeline();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  backgroundColor: const Color(0xFF1E293B),
                  content: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'JIT Pipeline Fired: STT ➔ MT ➔ Mesh ➔ TTS (${controller.selectedLanguage.toUpperCase()})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
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
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.error.withAlpha(50),
                    blurRadius: 10,
                  ),
                ],
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

          // STT Engine Readiness Indicator
          if (!controller.isSttReady)
            Container(
              width: double.infinity,
              color: controller.isSttInitializing
                  ? Colors.amber.withAlpha(25)
                  : theme.colorScheme.errorContainer.withAlpha(80),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  if (controller.isSttInitializing)
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                    )
                  else
                    Icon(Icons.mic_off_rounded, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.isSttInitializing
                          ? 'Loading STT engine (IndicConformer)...'
                          : 'STT engine not loaded — PTT will not work. Download models from Settings.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: controller.isSttInitializing
                            ? Colors.amber
                            : theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Message & Transcript Stream
          Expanded(
            child: controller.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withAlpha(20),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.speaker_phone_rounded,
                            size: 48,
                            color: theme.colorScheme.primary.withAlpha(160),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'No transmissions yet.\nHold Push-To-Talk to speak.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

          // Transmitting Bitrate Status with Waveform
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: controller.isTransmitting
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 16),
            secondChild: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _WaveformBars(controller: _waveController),
                      const SizedBox(width: 8),
                      Text(
                        'Transmitting semantic voice payload (~160 bps)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _WaveformBars(controller: _waveController),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Translation Mode Indicator & Quick Switch Pill + RUN JIT Trigger + NORM Mode Switch
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => controller.toggleMt(),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    margin: const EdgeInsets.only(top: 2, bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: controller.isMtEnabled
                          ? theme.colorScheme.primaryContainer.withAlpha(40)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: controller.isMtEnabled
                            ? theme.colorScheme.primary.withAlpha(120)
                            : theme.colorScheme.outline.withAlpha(60),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.translate_rounded,
                          size: 14,
                          color: controller.isMtEnabled
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          controller.isMtEnabled
                              ? 'MT ACTIVE: Translating to ${_languages.firstWhere((l) => l.$1 == controller.selectedLanguage, orElse: () => ('', controller.selectedLanguage)).$2}'
                              : 'MT BYPASSED: Direct Audio Passthrough',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: controller.isMtEnabled
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          controller.isMtEnabled ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                          size: 20,
                          color: controller.isMtEnabled
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // TTS Engine Quick-Switch (AI4Bharat Rasa-13 ↔ Meta MMS)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: InkWell(
                    onTap: () => controller.toggleTtsEngine(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: controller.isRasa
                            ? const Color(0xFFE65100).withAlpha(35)
                            : const Color(0xFF0288D1).withAlpha(35),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: controller.isRasa
                              ? const Color(0xFFFF9800).withAlpha(160)
                              : const Color(0xFF29B6F6).withAlpha(160),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            controller.isRasa ? Icons.hub_rounded : Icons.language_rounded,
                            size: 14,
                            color: controller.isRasa
                                ? const Color(0xFFFF9800)
                                : const Color(0xFF29B6F6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            controller.isRasa ? 'TTS: RASA' : 'TTS: MMS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: controller.isRasa
                                  ? const Color(0xFFFF9800)
                                  : const Color(0xFF29B6F6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // VAD (Voice Activity Detection) Hands-Free Quick Toggle
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: InkWell(
                    onTap: () => controller.toggleVadMode(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: controller.isVadMode
                            ? (controller.isVoiceDetected
                                ? Colors.green.withAlpha(50)
                                : theme.colorScheme.primary.withAlpha(35))
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: controller.isVadMode
                              ? (controller.isVoiceDetected ? Colors.green : theme.colorScheme.primary)
                              : theme.colorScheme.outline.withAlpha(80),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            controller.isVadMode ? Icons.record_voice_over_rounded : Icons.voice_over_off_rounded,
                            size: 14,
                            color: controller.isVadMode
                                ? (controller.isVoiceDetected ? Colors.greenAccent : theme.colorScheme.primary)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            controller.isVadMode
                                ? (controller.isVoiceDetected ? 'VOICE!' : 'VAD ON')
                                : 'VAD OFF',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: controller.isVadMode
                                  ? (controller.isVoiceDetected ? Colors.greenAccent : theme.colorScheme.primary)
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Normalizer 3-Mode Quick Toggle Button
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: InkWell(
                    onTap: () {
                      controller.toggleNormalizerMode();
                      final normColor = controller.isAdvancedNormalizer
                          ? const Color(0xFF00E5FF)
                          : (controller.isLegacyNormalizer ? Colors.amberAccent : const Color(0xFFD500F9));
                      final normIcon = controller.isAdvancedNormalizer
                          ? Icons.auto_awesome_rounded
                          : (controller.isLegacyNormalizer ? Icons.rule_rounded : Icons.psychology_rounded);
                      final normTitle = controller.isAdvancedNormalizer
                          ? 'Normalizer: ADVANCED (Phonological Matrix / Instant)'
                          : (controller.isLegacyNormalizer
                              ? 'Normalizer: LEGACY (Rule-Based ISCII Offset)'
                              : 'Normalizer: NEURAL INDIC_XLIT (AI4Bharat Aksharantar / Neural Mode)');

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          backgroundColor: const Color(0xFF1E293B),
                          content: Row(
                            children: [
                              Icon(normIcon, color: normColor, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  normTitle,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: controller.isAdvancedNormalizer
                            ? const Color(0xFF00E5FF).withAlpha(35)
                            : (controller.isLegacyNormalizer
                                ? Colors.amber.withAlpha(35)
                                : const Color(0xFFD500F9).withAlpha(35)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: controller.isAdvancedNormalizer
                              ? const Color(0xFF00E5FF).withAlpha(160)
                              : (controller.isLegacyNormalizer
                                  ? Colors.amberAccent.withAlpha(160)
                                  : const Color(0xFFD500F9).withAlpha(160)),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            controller.isAdvancedNormalizer
                                ? Icons.auto_awesome_rounded
                                : (controller.isLegacyNormalizer ? Icons.rule_rounded : Icons.psychology_rounded),
                            size: 14,
                            color: controller.isAdvancedNormalizer
                                ? const Color(0xFF00E5FF)
                                : (controller.isLegacyNormalizer ? Colors.amberAccent : const Color(0xFFD500F9)),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            controller.isAdvancedNormalizer
                                ? 'NORM: ADV'
                                : (controller.isLegacyNormalizer ? 'NORM: RULE' : 'NORM: XLIT'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: controller.isAdvancedNormalizer
                                  ? const Color(0xFF00E5FF)
                                  : (controller.isLegacyNormalizer ? Colors.amberAccent : const Color(0xFFD500F9)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Dedicated JIT Pipeline Trigger Button
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: InkWell(
                    onTap: () {
                      controller.triggerJitPipeline();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          backgroundColor: const Color(0xFF1E293B),
                          content: Row(
                            children: [
                              const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'JIT Pipeline Triggered: STT ➔ MT (${controller.selectedLanguage.toUpperCase()}) ➔ Mesh ➔ TTS',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(35),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.amberAccent.withAlpha(160),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.bolt_rounded, size: 14, color: Colors.amberAccent),
                          SizedBox(width: 4),
                          Text(
                            'RUN JIT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Live VAD (Voice Activity Detection) Status Badge
          Container(
            margin: const EdgeInsets.only(top: 2, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: controller.isVoiceDetected
                  ? Colors.green.withAlpha(40)
                  : (controller.isVadMode ? Colors.blue.withAlpha(25) : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: controller.isVoiceDetected
                    ? Colors.greenAccent
                    : (controller.isVadMode ? Colors.blueAccent.withAlpha(100) : Colors.transparent),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: controller.isVoiceDetected
                        ? Colors.greenAccent
                        : (controller.isVadMode ? Colors.amberAccent : Colors.grey.withAlpha(120)),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  controller.isVoiceDetected
                      ? 'VAD: VOICE DETECTED (Capturing Speech)'
                      : (controller.isVadMode
                          ? 'VAD ACTIVE: Listening Hands-Free...'
                          : (controller.isTransmitting ? 'VAD: SILENCE (Pauses Gated)' : 'VAD: READY')),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: controller.isVoiceDetected
                        ? Colors.greenAccent
                        : (controller.isVadMode ? Colors.amberAccent : theme.colorScheme.onSurfaceVariant.withAlpha(160)),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Large Push-To-Talk / VAD Hands-Free Button with Radar Pulse Rings
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 26),
            child: GestureDetector(
              onTap: controller.isVadMode ? () => controller.toggleVadMode() : null,
              onTapDown: controller.isVadMode ? null : (_) => controller.onPttPressed(),
              onTapUp: controller.isVadMode ? null : (_) => controller.onPttReleased(),
              onTapCancel: controller.isVadMode ? null : () => controller.onPttReleased(),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer radar pulse ring when transmitting or voice detected
                  if (controller.isTransmitting || controller.isVoiceDetected)
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 124 * (1.0 + (_pulseController.value * 0.35)),
                          height: 124 * (1.0 + (_pulseController.value * 0.35)),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: (controller.isVoiceDetected ? Colors.green : theme.colorScheme.error)
                                  .withAlpha(((1.0 - _pulseController.value) * 130).round()),
                              width: 2.0,
                            ),
                          ),
                        );
                      },
                    ),

                  // Main Button Circle
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 124,
                      height: 124,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: controller.isSttInitializing
                              ? [Colors.amber.shade700, Colors.orange.shade900]
                              : (!controller.isSttReady && !controller.isVadMode)
                                  ? [Colors.grey.shade600, Colors.grey.shade800]
                                  : controller.isVadMode
                                      ? (controller.isVoiceDetected
                                          ? [const Color(0xFF00C853), const Color(0xFF1B5E20)]
                                          : [const Color(0xFF00897B), const Color(0xFF004D40)])
                                      : (controller.isTransmitting
                                          ? [theme.colorScheme.error, const Color(0xFFB71C1C)]
                                          : [theme.colorScheme.primary, const Color(0xFF0D47A1)]),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (controller.isSttInitializing
                                    ? Colors.amber
                                    : (!controller.isSttReady && !controller.isVadMode)
                                        ? Colors.grey
                                        : controller.isVadMode
                                            ? (controller.isVoiceDetected ? Colors.green : Colors.teal)
                                            : (controller.isTransmitting ? theme.colorScheme.error : theme.colorScheme.primary))
                                .withAlpha(controller.isTransmitting || controller.isVoiceDetected ? 160 : 90),
                            blurRadius: controller.isTransmitting || controller.isVoiceDetected ? 28 : 16,
                            spreadRadius: controller.isTransmitting || controller.isVoiceDetected ? 4 : 1,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (controller.isSttInitializing)
                            const SizedBox(
                              width: 36, height: 36,
                              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                            )
                          else
                            Icon(
                              (!controller.isSttReady && !controller.isVadMode)
                                  ? Icons.mic_off_rounded
                                  : controller.isVadMode
                                      ? (controller.isVoiceDetected ? Icons.record_voice_over_rounded : Icons.hearing_rounded)
                                      : (controller.isTransmitting ? Icons.mic_rounded : Icons.mic_none_rounded),
                              size: 44,
                              color: Colors.white,
                            ),
                          const SizedBox(height: 4),
                          Text(
                            controller.isSttInitializing
                                ? 'LOADING...'
                                : (!controller.isSttReady && !controller.isVadMode)
                                    ? 'STT NEEDED'
                                    : controller.isVadMode
                                        ? (controller.isVoiceDetected ? 'SPEAKING' : 'VAD ACTIVE')
                                        : (controller.isTransmitting ? 'RECORDING' : 'HOLD PTT'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          if (controller.isVadMode)
                            const Text(
                              '(Hands-free)',
                              style: TextStyle(fontSize: 8.5, color: Colors.white70, fontWeight: FontWeight.w500),
                            ),
                          if (controller.isSttReady && !controller.isVadMode && !controller.isTransmitting)
                            Text(
                              '\u2713 STT Ready',
                              style: TextStyle(fontSize: 8.5, color: Colors.greenAccent.withAlpha(200), fontWeight: FontWeight.w500),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  final AnimationController controller;

  const _WaveformBars({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(4, (index) {
            final phase = (controller.value + (index * 0.25)) % 1.0;
            final height = 6.0 + (math.sin(phase * 2 * math.pi).abs() * 12.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 2.8,
              height: height,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
