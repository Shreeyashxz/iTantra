import 'package:flutter/material.dart';

/// Giant Glowing Tactile Push-To-Talk (PTT) Button for ELI-5 Walkie-Talkie UI.
class PttButton extends StatefulWidget {
  final bool isTransmitting;
  final VoidCallback onPressDown;
  final VoidCallback onPressUp;
  final bool enabled;

  const PttButton({
    super.key,
    required this.isTransmitting,
    required this.onPressDown,
    required this.onPressUp,
    this.enabled = true,
  });

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 8.0, end: 28.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant PttButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTransmitting && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isTransmitting && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBroadcasting = widget.isTransmitting;
    final shadowColor = isBroadcasting ? Colors.redAccent : const Color(0xFF00E676);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = isBroadcasting ? _scaleAnimation.value : 1.0;
        final glowRadius = isBroadcasting ? _glowAnimation.value : 10.0;

        return Transform.scale(
          scale: scale,
          child: GestureDetector(
            onTapDown: widget.enabled ? (_) => widget.onPressDown() : null,
            onTapUp: widget.enabled ? (_) => widget.onPressUp() : null,
            onTapCancel: widget.enabled ? widget.onPressUp : null,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isBroadcasting
                      ? [const Color(0xFFFF5252), const Color(0xFFD50000)]
                      : [const Color(0xFF00E676), const Color(0xFF00B248)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withAlpha(isBroadcasting ? 160 : 70),
                    blurRadius: glowRadius,
                    spreadRadius: isBroadcasting ? 6 : 2,
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withAlpha(isBroadcasting ? 220 : 120),
                  width: 3.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isBroadcasting ? Icons.radio_button_checked : Icons.mic_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isBroadcasting ? 'SPEAKING' : 'HOLD TO TALK',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
