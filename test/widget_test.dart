// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_native_im_ai/app/app.dart';

void main() {
  testWidgets('App renders shell', (WidgetTester tester) async {
    await tester.pumpWidget(const AiimApp());

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('聊天室'), findsOneWidget);
    expect(find.text('AI聊天'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
