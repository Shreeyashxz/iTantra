import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/transceiver_controller.dart';
import '../../speech/indic_xlit_engine.dart';
import '../../speech/indiclid_fasttext_engine.dart';
import '../../speech/neural_mt_engine.dart';
import '../../speech/pipeline_config.dart';
import '../../speech/silero_vad_engine.dart';

/// Voice pipeline control center: force switches + flow diagram + warnings + RAM pie.
/// Mounted at the top of SettingsScreen. Downloads stay in the existing model cards;
/// this card controls what is *loaded in RAM* right now.
class PipelineDiagramCard extends StatefulWidget {
  const PipelineDiagramCard({super.key});

  @override
  State<PipelineDiagramCard> createState() => _PipelineDiagramCardState();
}

class _PipelineDiagramCardState extends State<PipelineDiagramCard> {
  final Set<String> _busy = {};

  bool _isBusy(String key) => _busy.contains(key);
  Future<void> _run(BuildContext context, String key, Future<String?> Function() fn) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      final err = await fn();
      if (!context.mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: const Color(0xFF7F1D1D)),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pipeline switch failed: $e'), backgroundColor: const Color(0xFF7F1D1D)),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  PipelineSnapshot _snapshot(SettingsController s, TransceiverController t) {
    final speech = t.speechEngine;
    return PipelineSnapshot(
      sttLoaded: speech.isSttLoaded,
      sttPrecision: s.settings.sttPrecision,
      ttsLoaded: t.ttsEngineType == 'OS_NATIVE' ? true : speech.isTtsLoaded,
      ttsEngine: t.ttsEngineType,
      mtNeuralReady: NeuralMtEngine.instance.isReady,
      mtEnabled: t.isMtEnabled,
      xlitNeuralReady: IndicXlitEngine.instance.isNeuralActive,
      normalizerMode: t.normalizerMode,
      lidReady: IndicLIDFastTextEngine.instance.isNeuralActive,
      vadNeural: _vadNeural(t),
      autoPlayAudio: s.settings.autoPlayAudio,
      selectedLang: t.selectedLanguage,
    );
  }

  bool _vadNeural(TransceiverController t) {
    final vad = t.commPipeline.vadEngine;
    if (vad is SileroVadEngine) return vad.isNeuralActive;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();
    final transceiver = context.watch<TransceiverController>();
    final snap = _snapshot(settings, transceiver);
    final warnings = PipelineModel.validate(snap);
    final slices = PipelineModel.ramSlices(snap);
    final total = PipelineModel.totalRamMb(snap);
    final errors = warnings.where((w) => w.severity == PipelineSeverity.error).length;
    final warns = warnings.where((w) => w.severity == PipelineSeverity.warning).length;

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree_rounded, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Voice Pipeline — live switches',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                _HealthChip(errors: errors, warns: warns),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Mic → VAD gate → STT → Xlit → MT → TTS → Speaker. Switches force load/unload in RAM now (downloads stay below).',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // Flow diagram strip
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FlowNode(icon: Icons.mic_rounded, label: 'MIC', on: true, color: Colors.greenAccent),
                  _FlowArrow(),
                  _FlowNode(
                    icon: Icons.hearing_rounded,
                    label: 'VAD${snap.vadNeural ? '' : '*'}',
                    on: true,
                    color: snap.vadNeural ? Colors.greenAccent : Colors.amberAccent,
                  ),
                  _FlowArrow(),
                  _FlowNode(icon: Icons.record_voice_over_rounded, label: 'STT', on: snap.sttLoaded, color: Colors.cyanAccent),
                  _FlowArrow(),
                  _FlowNode(
                    icon: Icons.translate_rounded,
                    label: snap.normalizerMode == 'NEURAL_INDIC_XLIT' ? 'XLIT' : 'NORM',
                    on: true,
                    color: snap.normalizerMode == 'NEURAL_INDIC_XLIT'
                        ? (snap.xlitNeuralReady ? const Color(0xFFD500F9) : Colors.amberAccent)
                        : Colors.cyanAccent,
                  ),
                  _FlowArrow(),
                  _FlowNode(icon: Icons.language_rounded, label: 'MT', on: snap.mtEnabled, color: Colors.lightBlueAccent),
                  _FlowArrow(),
                  _FlowNode(icon: Icons.volume_up_rounded, label: 'TTS', on: snap.ttsLoaded, color: Colors.tealAccent),
                  _FlowArrow(),
                  _FlowNode(icon: Icons.speaker_rounded, label: 'SPK', on: snap.autoPlayAudio, color: Colors.greenAccent),
                ],
              ),
            ),
            if (!snap.vadNeural)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('* VAD neural off — RMS fallback',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 12),
            // Force switches
            _StageSwitch(
              icon: Icons.record_voice_over_rounded,
              title: 'STT ${snap.sttPrecision} — ${snap.sttLoaded ? 'loaded' : 'OFF'}',
              subtitle: snap.sttLoaded ? 'Unloads recognizer from RAM' : 'Loads recognizer into RAM now',
              value: snap.sttLoaded,
              busy: _isBusy('stt'),
              onChanged: (v) => _run(context, 'stt', () async {
                if (v) {
                  final ok = await transceiver.speechEngine.initStt(settings.settings.sttPrecision);
                  await settings.checkModelStatus();
                  if (!transceiver.speechEngine.isSttLoaded || !ok) {
                    return 'STT model not downloaded — use the STT download card below, then retry.';
                  }
                  return null;
                } else {
                  transceiver.speechEngine.unloadStt();
                  await settings.checkModelStatus();
                  return null;
                }
              }),
            ),
            _StageSwitch(
              icon: Icons.volume_up_rounded,
              title: 'TTS ${snap.ttsEngine} — ${snap.ttsLoaded ? 'loaded' : 'OFF'}',
              subtitle: 'Rasa-13 / MMS / OS switch is in Transceiver; this forces load/unload',
              value: snap.ttsLoaded,
              busy: _isBusy('tts'),
              onChanged: (v) => _run(context, 'tts', () async {
                if (v) {
                  final ok = await transceiver.speechEngine.initTts(transceiver.selectedLanguage, transceiver.ttsEngineType);
                  await settings.checkModelStatus();
                  if (!transceiver.speechEngine.isTtsLoaded || !ok) {
                    return 'TTS voice not downloaded for ${transceiver.selectedLanguage} — use the TTS download cards below, or switch engine to OS_NATIVE.';
                  }
                  return null;
                } else {
                  transceiver.speechEngine.unloadTts();
                  await settings.checkModelStatus();
                  return null;
                }
              }),
            ),
            _StageSwitch(
              icon: Icons.language_rounded,
              title: 'MT translate — ${snap.mtEnabled ? 'ON' : 'OFF'}',
              subtitle: snap.mtNeuralReady ? 'Neural weights live (full sentences)' : 'Lexicon fallback (<1ms tactical)',
              value: snap.mtEnabled,
              busy: _isBusy('mt'),
              onChanged: (v) => _run(context, 'mt', () async {
                await settings.updateMtEnabled(v);
                return null;
              }),
            ),
            _StageSwitch(
              icon: Icons.psychology_rounded,
              title: 'Xlit ${snap.normalizerMode} — ${snap.xlitNeuralReady ? 'neural' : 'rules'}',
              subtitle: 'ON = NEURAL_INDIC_XLIT mode (fallback works offline); OFF = ADVANCED',
              value: snap.normalizerMode == 'NEURAL_INDIC_XLIT',
              busy: _isBusy('xlit'),
              onChanged: (v) => _run(context, 'xlit', () async {
                await transceiver.setNormalizerMode(v ? 'NEURAL_INDIC_XLIT' : 'ADVANCED');
                await settings.checkModelStatus();
                return null;
              }),
            ),
            _StageSwitch(
              icon: Icons.hearing_rounded,
              title: 'VAD neural gate — ${snap.vadNeural ? 'neural' : 'RMS fallback'}',
              subtitle: 'OFF still captures via energy gate; neural is better in noise',
              value: snap.vadNeural,
              busy: _isBusy('vad'),
              onChanged: (v) => _run(context, 'vad', () async {
                final vad = transceiver.commPipeline.vadEngine;
                if (vad is SileroVadEngine) {
                  if (v) {
                    final ok = await vad.initNeuralVad();
                    if (!ok) return 'Neural VAD bundle missing — RMS fallback stays active.';
                  } else {
                    vad.unloadNeuralVad();
                  }
                  return null;
                }
                return 'VAD engine does not support neural toggle on this build.';
              }),
            ),
            _StageSwitch(
              icon: Icons.label_rounded,
              title: 'Language-ID — ${snap.lidReady ? 'neural' : 'heuristic'}',
              subtitle: 'Auto-corrects wrong language tags on inbound packets',
              value: snap.lidReady,
              busy: _isBusy('lid'),
              onChanged: (v) => _run(context, 'lid', () async {
                if (v) {
                  final ok = await IndicLIDFastTextEngine.instance.init();
                  await settings.checkModelStatus();
                  if (!ok) return 'LID weights not downloaded (~14MB) — heuristic stays active. Use the LID download card below.';
                  return null;
                } else {
                  IndicLIDFastTextEngine.instance.unload();
                  await settings.checkModelStatus();
                  return null;
                }
              }),
            ),
            _StageSwitch(
              icon: Icons.speaker_rounded,
              title: 'Auto-play speaker — ${snap.autoPlayAudio ? 'ON' : 'muted'}',
              subtitle: 'OFF = text-only walkie-talkie (lowest RAM/CPU)',
              value: snap.autoPlayAudio,
              busy: _isBusy('spk'),
              onChanged: (v) => _run(context, 'spk', () async {
                await settings.updateAutoPlayAudio(v);
                return null;
              }),
            ),
            const SizedBox(height: 12),
            // Warnings
            Text('Composition checks', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (warnings.isEmpty)
              const _WarningTile(
                icon: Icons.check_circle_rounded,
                color: Colors.greenAccent,
                text: 'Healthy composition — no conflicts.',
              )
            else
              ...warnings.map((w) => _WarningTile(
                    icon: w.severity == PipelineSeverity.error
                        ? Icons.error_rounded
                        : w.severity == PipelineSeverity.warning
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline_rounded,
                    color: w.severity == PipelineSeverity.error
                        ? Colors.redAccent
                        : w.severity == PipelineSeverity.warning
                            ? Colors.amberAccent
                            : Colors.lightBlueAccent,
                    text: '[${w.stageId.toUpperCase()}] ${w.message}',
                  )),
            const SizedBox(height: 12),
            // RAM pie
            Text('RAM in use (est.) — ${total.round()} MB', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                RamPieChart(slices: slices, totalMb: total),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in slices)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Container(width: 10, height: 10, color: _sliceColor(s.stageId)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${s.label} — ${s.active ? '${s.mb.round()}MB' : 'off'}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: s.active ? null : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Estimates = file size + ORT overhead. >800MB warns for 2–3GB field phones.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
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

class _HealthChip extends StatelessWidget {
  final int errors;
  final int warns;
  const _HealthChip({required this.errors, required this.warns});

  @override
  Widget build(BuildContext context) {
    final ok = errors == 0 && warns == 0;
    final color = errors > 0 ? Colors.redAccent : warns > 0 ? Colors.amberAccent : Colors.greenAccent;
    final label = errors > 0 ? '$errors ERR' : warns > 0 ? '$warns WARN' : 'HEALTHY';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(160)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _FlowNode extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final Color color;
  const _FlowNode({required this.icon, required this.label, required this.on, required this.color});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: on ? 1.0 : 0.45,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withAlpha(35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withAlpha(on ? 200 : 90), width: on ? 2 : 1),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          Text(on ? 'ON' : 'OFF',
              style: TextStyle(fontSize: 9, color: on ? Colors.greenAccent : Colors.redAccent)),
        ],
      ),
    );
  }
}

class _FlowArrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white38),
    );
  }
}

class _StageSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;
  const _StageSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (busy)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _WarningTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _WarningTile({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

Color _sliceColor(String id) {
  switch (id) {
    case 'base':
      return Colors.white24;
    case 'stt':
      return Colors.cyanAccent;
    case 'tts':
      return Colors.tealAccent;
    case 'mt':
      return Colors.lightBlueAccent;
    case 'xlit':
      return const Color(0xFFD500F9);
    case 'lid':
      return Colors.orangeAccent;
    case 'vad':
      return Colors.greenAccent;
    default:
      return Colors.white38;
  }
}

class RamPieChart extends StatelessWidget {
  final List<PipelineRamSlice> slices;
  final double totalMb;
  const RamPieChart({super.key, required this.slices, required this.totalMb});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(
        painter: _RamPiePainter(slices: slices.where((s) => s.active).toList()),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${totalMb.round()}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text('MB', style: TextStyle(fontSize: 10, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RamPiePainter extends CustomPainter {
  final List<PipelineRamSlice> slices;
  _RamPiePainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold(0.0, (a, b) => a + b.mb);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    if (total <= 0) {
      final p = Paint()..color = Colors.white12;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, p);
      return;
    }
    double start = -math.pi / 2;
    for (final s in slices) {
      final sweep = (s.mb / total) * math.pi * 2;
      final p = Paint()
        ..color = _sliceColor(s.stageId)
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, start, sweep, true, p);
      start += sweep;
    }
    // Donut hole
    final hole = Paint()..color = const Color(0xFF131A29);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width * 0.32, hole);
  }

  @override
  bool shouldRepaint(covariant _RamPiePainter old) => old.slices != slices;
}
