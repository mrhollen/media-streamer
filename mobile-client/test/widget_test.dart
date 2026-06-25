// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:media_streamer_client/main.dart';
import 'package:media_streamer_client/providers/server_provider.dart';
import 'package:media_streamer_client/services/api_service.dart';
import 'package:media_streamer_client/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App loads with empty server list', (WidgetTester tester) async {
    // Set up mock SharedPreferences for the test environment
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ServerProvider(
          StorageService(prefs),
          ApiService(),
        ),
        child: const MediaStreamerApp(),
      ),
    );

    // Allow async initialization to complete
    await tester.pumpAndSettle();

    // Verify the app title is present
    expect(find.text('Media Streamer'), findsOneWidget);

    // Verify empty state message is shown
    expect(find.text('No servers yet'), findsOneWidget);
  });
}
