import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ar_road_nav/main.dart';

void main() {
  testWidgets('App launches correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const ARRoadNavApp());

    // Verify the app title renders
    expect(find.text('AR ROAD NAVIGATOR'), findsOneWidget);
  });
}
