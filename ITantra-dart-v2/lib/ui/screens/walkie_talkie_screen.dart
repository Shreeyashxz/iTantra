import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/transceiver_controller.dart';
import '../../data/entities/message_entity.dart';
import '../../speech/indiclid_fasttext_engine.dart';
import '../widgets/ptt_button.dart';
import 'dev_diagnostics_screen.dart';
import 'settings_screen.dart';

/// ELI-5 Tactical Walkie-Talkie Screen (iTantra v2 Core User Interface).
/// Simple enough for a 5-year-old or an exhausted first responder:
/// - Giant glowing PTT button in center
/// - Clear language indicator with FastText Auto-detect
/// - Instant speech bubbles with auto-detected language badges
/// - 1-tap Emergency SOS & Quick Preset phrases
/// - Toggle to switch to Classic UI mode anytime
class WalkieTalkieScreen extends StatefulWidget {
  final VoidCallback onSwitchToClassicUi;

  const WalkieTalkieScreen({
    super.key,
    required this.onSwitchToClassicUi,
  });

  @override
  State<WalkieTalkieScreen> createState() => _WalkieTalkieScreenState();
}

class _WalkieTalkieScreenState extends State<WalkieTalkieScreen> {
  final ScrollController _scrollController = ScrollController();

  static const List<Map<String, String>> _quickPhrases = [
    {'icon': '🚑', 'label': 'Need Doctor', 'text': 'Emergency! Medical doctor needed immediately.'},
    {'icon': '💧', 'label': 'Water & Food', 'text': 'Supplies needed: Drinking water and emergency rations.'},
    {'icon': '⚠️', 'label': 'Danger', 'text': 'Immediate hazard or collapse risk in this area.'},
    {'icon': '📍', 'label': 'Coordinates', 'text': 'Requesting status update and coordinates confirmation.'},
    {'icon': '🆗', 'label': 'All Safe', 'text': 'Unit is secure. All individuals safe and accounted for.'},
  ];

  @override
  Widget build(BuildContext context) {
    final transceiver = context.watch<TransceiverController>();
    final settings = context.watch<SettingsController>();
    final isTransmitting = transceiver.isTransmitting;
    final messages = transceiver.messages;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: _buildTopAppBar(context, transceiver),
      body: SafeArea(
        child: Column(
          children: [
            // 1. ELI-5 Language Bar: My Language + Auto-Detect
            _buildLanguagePillsBar(context, settings),

            // 2. Conversation Feed
            Expanded(
              child: messages.isEmpty
                  ? _buildEmptyState()
                  : _buildMessageFeed(messages, settings.preferredLanguage),
            ),

            // 3. Quick Emergency Phrases Ribbon
            _buildQuickPhrasesRibbon(context, transceiver),

            // 4. Bottom Giant PTT Station
            _buildPttStation(context, transceiver, isTransmitting),
          ],
        ),
      ),
    );
  }

  /// Top Bar with Status, Dev Mode Icon, UI Switcher, and SOS Button
  PreferredSizeWidget _buildTopAppBar(BuildContext context, TransceiverController transceiver) {
    return AppBar(
      backgroundColor: const Color(0xFF161B22),
      elevation: 0,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF3FB950),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0xFF3FB950), blurRadius: 6, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'iTantra Walkie-Talkie',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              Text(
                '🟢 Mesh Connected (${transceiver.connectionStatus})',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Switch to Classic Multi-Tab UI Button
        IconButton(
          tooltip: 'Switch to Classic UI',
          icon: const Icon(Icons.dashboard_customize_outlined, color: Color(0xFF58A6FF)),
          onPressed: widget.onSwitchToClassicUi,
        ),

        // Settings
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined, color: Color(0xFFC9D1D9)),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
        ),

        // Deep Dev Diagnostics Window (NOT ELI-5)
        IconButton(
          tooltip: 'Developer Diagnostics & RAM Meter',
          icon: const Icon(Icons.terminal_rounded, color: Color(0xFFE3B341)),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DevDiagnosticsScreen()),
            );
          },
        ),

        // Emergency SOS Button
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 4),
          child: ElevatedButton(
            onPressed: () => _sendEmergencySos(context, transceiver),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF334B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 16),
                SizedBox(width: 4),
                Text('SOS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Simple 2-Pill Language Bar
  Widget _buildLanguagePillsBar(BuildContext context, SettingsController settings) {
    final currentLangCode = settings.preferredLanguage;
    final currentLangName = IndicLIDFastTextEngine.languageNames[currentLangCode] ?? currentLangCode.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: Color(0xFF30363D), width: 1)),
      ),
      child: Row(
        children: [
          // Pill 1: My Language
          Expanded(
            child: InkWell(
              onTap: () => _showLanguageSelectorSheet(context, settings),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF21262D),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF388BFD)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_pin_rounded, size: 16, color: Color(0xFF58A6FF)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'I Hear: $currentLangName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Color(0xFF58A6FF), size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Pill 2: Incoming Auto-Detect (FastText)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF778BA).withAlpha(150)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 14, color: Color(0xFFF778BA)),
                SizedBox(width: 6),
                Text(
                  'Auto-Detect (FastText ⚡)',
                  style: TextStyle(
                    color: Color(0xFFF778BA),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Empty Feed State
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: const Icon(Icons.radio_rounded, size: 48, color: Color(0xFF58A6FF)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Channel Ready',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Hold the button below to talk to nearby radios.\nSpeak in any language — FastText translates automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// Conversation Stream Feed
  Widget _buildMessageFeed(List<MessageEntity> messages, String myLang) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isMe = !msg.isIncoming;

        // Auto-detect language of incoming text with IndicLID-FastText
        final detected = IndicLIDFastTextEngine.instance.identifyLanguage(msg.text);
        final langBadge = detected.languageCode.toUpperCase();

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF1F6FEB).withAlpha(40) : const Color(0xFF161B22),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
              border: Border.all(
                color: isMe ? const Color(0xFF388BFD) : const Color(0xFF30363D),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMe ? Icons.account_circle : Icons.cell_tower,
                      size: 14,
                      color: isMe ? const Color(0xFF58A6FF) : const Color(0xFF3FB950),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isMe ? 'You' : msg.senderId,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isMe ? const Color(0xFF58A6FF) : const Color(0xFF3FB950),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Detected Language Badge via IndicLID FastText
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF778BA).withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFF778BA).withAlpha(120)),
                      ),
                      child: Text(
                        'LID: $langBadge',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF778BA),
                        ),
                      ),
                    ),

                    const Spacer(),
                    Text(
                      DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(msg.timestamp)),
                      style: const TextStyle(fontSize: 10, color: Color(0xFF8B949E)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Main Message Text
                Text(
                  msg.text,
                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Quick Emergency Presets Ribbon
  Widget _buildQuickPhrasesRibbon(BuildContext context, TransceiverController transceiver) {
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _quickPhrases.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = _quickPhrases[i];
          return ActionChip(
            backgroundColor: const Color(0xFF21262D),
            side: const BorderSide(color: Color(0xFF30363D)),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item['icon']!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  item['label']!,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            onPressed: () {
              transceiver.sendTextMessage(item['text']!);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Broadcasted: ${item['label']}'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Bottom Station with PTT Button
  Widget _buildPttStation(BuildContext context, TransceiverController transceiver, bool isTransmitting) {
    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      child: Center(
        child: PttButton(
          isTransmitting: isTransmitting,
          onPressDown: () => transceiver.onPttPressed(),
          onPressUp: () => transceiver.onPttReleased(),
        ),
      ),
    );
  }

  /// Emergency SOS Dispatch Modal
  void _sendEmergencySos(BuildContext context, TransceiverController transceiver) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text('Transmit SOS Alert?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This broadcasts a maximum-priority emergency beacon to every connected walkie-talkie within radio mesh range.',
          style: TextStyle(color: Color(0xFF8B949E), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              transceiver.sendTextMessage('🚨 SOS EMERGENCY! Immediate assistance requested at this position.');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Colors.red,
                  content: Text('🚨 SOS Alert Broadcasted Across Mesh!'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('TRANSMIT SOS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Language Picker Bottom Sheet
  void _showLanguageSelectorSheet(BuildContext context, SettingsController settings) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Select Your Language',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(color: Color(0xFF30363D), height: 1),
              Expanded(
                child: ListView(
                  children: IndicLIDFastTextEngine.languageNames.entries.map((entry) {
                    final isSelected = settings.preferredLanguage == entry.key;
                    return ListTile(
                      title: Text(
                        entry.value,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF58A6FF) : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF58A6FF))
                          : null,
                      onTap: () {
                        settings.setPreferredLanguage(entry.key);
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
