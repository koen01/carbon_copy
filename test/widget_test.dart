import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carbon_copy/main.dart';

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const CarbonCopyApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
