import 'package:flutter/material.dart';
import '../../data/app_database.dart';
import 'home_screen.dart';
import 'language_setup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _navigateToNext();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;

    bool isFirstLaunch = false;
    try {
      final settings = await AppDatabase.instance
          .getSettings()
          .timeout(const Duration(milliseconds: 400));
      isFirstLaunch = !settings.installedLanguagePacks.contains('SETUP_DONE');
    } catch (_) {}

    if (mounted) {
      _pulseController.stop();
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              isFirstLaunch ? const LanguageSetupScreen() : const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary,
              const Color(0xFF001026),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withAlpha(50), width: 1.5),
              ),
              child: const Icon(
                Icons.mic_none_rounded,
                size: 72,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'iTantra',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Multilingual Neural Transceiver',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withAlpha(220),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'SIH 26173 • ISRO Sponsored',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white.withAlpha(160),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Initializing offline ONNX runtimes...',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white.withAlpha(180),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
