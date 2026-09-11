import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:itantra_dart/ui/screens/splash_screen.dart';
import 'package:itantra_dart/ui/theme/app_theme.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

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
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 1000)));
    await tester.pumpAndSettle();

    // Verify what is on screen (either Calibration, Walkie-Talkie, or Dashboard)

    // Verify next screen loaded (either Calibration, Walkie-Talkie, or Dashboard)
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data?.contains('Dashboard') == true ||
             widget.data?.contains('Walkie-Talkie') == true ||
             widget.data == 'Initial Device Calibration'),
      ),
      findsWidgets,
    );
  });
}
