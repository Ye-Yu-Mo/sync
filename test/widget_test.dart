// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:sftp_sync_manager/main.dart';

void main() {
  testWidgets('App launches and shows task list', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SftpSyncApp());

    // Verify that the app bar title is displayed
    expect(find.text('SFTP 同步管理'), findsOneWidget);
  });
}
