import 'package:flutter/material.dart';
import '../../speech/ram_monitor_service.dart';

/// Real-time Live RAM Meter Widget for Developer Diagnostics Window.
/// Displays total process RSS memory, breakdown by neural engine, and flush controls.
class RamMeterWidget extends StatefulWidget {
  const RamMeterWidget({super.key});

  @override
  State<RamMeterWidget> createState() => _RamMeterWidgetState();
}

class _RamMeterWidgetState extends State<RamMeterWidget> {
  late RamStats _stats;

  @override
  void initState() {
    super.initState();
    RamMonitorService.instance.startMonitoring();
    _stats = RamMonitorService.instance.currentStats;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RamStats>(
      stream: RamMonitorService.instance.statsStream,
      initialData: _stats,
      builder: (context, snapshot) {
        final stats = snapshot.data ?? _stats;
        final totalMb = stats.totalProcessRssMb;
        final neuralMb = stats.totalNeuralModelsRamMb;

        return Card(
          color: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF30363D)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.memory, color: Color(0xFF58A6FF), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Live RAM Meter & Engine Footprint',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: totalMb > 600 ? Colors.red.withAlpha(50) : const Color(0xFF238636).withAlpha(50),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: totalMb > 600 ? Colors.redAccent : const Color(0xFF3FB950),
                        ),
                      ),
                      child: Text(
                        'Total: ${totalMb.toStringAsFixed(1)} MB',
                        style: TextStyle(
                          color: totalMb > 600 ? Colors.redAccent : const Color(0xFF3FB950),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Multi-segment Memory Usage Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 14,
                    child: Row(
                      children: [
                        if (stats.sttRamMb > 0)
                          _buildSegment(stats.sttRamMb, totalMb, const Color(0xFF238636)),
                        if (stats.mtRamMb > 0)
                          _buildSegment(stats.mtRamMb, totalMb, const Color(0xFF1F6FEB)),
                        if (stats.ttsRamMb > 0)
                          _buildSegment(stats.ttsRamMb, totalMb, const Color(0xFF8957E5)),
                        if (stats.xlitRamMb > 0)
                          _buildSegment(stats.xlitRamMb, totalMb, const Color(0xFFD29922)),
                        if (stats.lidRamMb > 0)
                          _buildSegment(stats.lidRamMb, totalMb, const Color(0xFFF778BA)),
                        if (stats.vadRamMb > 0)
                          _buildSegment(stats.vadRamMb, totalMb, const Color(0xFF56D364)),
                        _buildSegment(stats.otherProcessRamMb, totalMb, const Color(0xFF484F58)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Per-Engine Memory Breakdown Badges
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildEngineBadge('STT (IndicConformer)', stats.sttRamMb, const Color(0xFF238636)),
                    _buildEngineBadge('MT (IndicTrans2)', stats.mtRamMb, const Color(0xFF1F6FEB)),
                    _buildEngineBadge('TTS (Meta MMS)', stats.ttsRamMb, const Color(0xFF8957E5)),
                    _buildEngineBadge('Xlit (IndicXlit)', stats.xlitRamMb, const Color(0xFFD29922)),
                    _buildEngineBadge('LID (IndicLID-FastText)', stats.lidRamMb, const Color(0xFFF778BA)),
                    _buildEngineBadge('VAD (Silero)', stats.vadRamMb, const Color(0xFF56D364)),
                    _buildEngineBadge('App & UI Runtime', stats.otherProcessRamMb, const Color(0xFF8B949E)),
                  ],
                ),
                const SizedBox(height: 14),

                // Action Controls
                Row(
                  children: [
                    Text(
                      'Active Models: ${neuralMb.toStringAsFixed(1)} MB',
                      style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () {
                        RamMonitorService.instance.flushInactiveEngines();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Flushed inactive neural models from RAM'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.cleaning_services, size: 14, color: Color(0xFFE3B341)),
                      label: const Text(
                        'Flush Unused RAM',
                        style: TextStyle(fontSize: 12, color: Color(0xFFE3B341)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE3B341)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        RamMonitorService.instance.reloadCoreEngines();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Core models reloaded into RAM'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('Reload Models', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF238636),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSegment(double mb, double totalMb, Color color) {
    if (totalMb <= 0 || mb <= 0) return const SizedBox.shrink();
    final flex = (mb * 1000 / totalMb).round().clamp(1, 1000);
    return Flexible(
      flex: flex,
      child: Container(
        color: color,
        height: 14,
      ),
    );
  }

  Widget _buildEngineBadge(String label, double mb, Color color) {
    final isLoaded = mb > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLoaded ? color : Colors.grey,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ${isLoaded ? "${mb.toStringAsFixed(0)} MB" : "0 MB (Offloaded)"}',
            style: TextStyle(
              fontSize: 11,
              color: isLoaded ? Colors.white : const Color(0xFF8B949E),
              fontWeight: isLoaded ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
