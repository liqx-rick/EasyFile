// This is a basic Flutter widget test for EasyFile app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/app.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';

void main() {
  testWidgets('EasyFile app basic test', (WidgetTester tester) async {
    // Initialize dependencies for testing
    await logger.init();
    setupLocator();

    // Build our app and trigger a frame.
    await tester.pumpWidget(const EasyFileApp());

    // Verify that the app title is displayed
    expect(find.text('EasyFile'), findsOneWidget);

    // Verify that we have a file browser page
    expect(find.byType(Scaffold), findsOneWidget);
  }, skip: true);

  tearDownAll(() async {
    // Clean up locator after all tests
    await locator.reset();
  });
}
