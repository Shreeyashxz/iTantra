import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itantra_dart/ui/screens/splash_screen.dart';
import 'package:itantra_dart/ui/theme/app_theme.dart';

void main() {
  testWidgets('SplashScreen displays brand elements and navigates', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );

    // Verify brand text elements on splash
    expect(find.text('iTantra'), findsOneWidget);
    expect(find.text('Multilingual Neural Transceiver'), findsOneWidget);
    expect(find.text('SIH 26173 • ISRO Sponsored'), findsOneWidget);

    // Advance splash duration and complete transition
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pumpAndSettle();

    // Verify HomeScreen dashboard loaded
    expect(find.text('iTantra Dashboard'), findsOneWidget);
  });
}
