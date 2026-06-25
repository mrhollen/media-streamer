import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/app_theme.dart';
import 'providers/server_provider.dart';
import 'services/storage_service.dart';
import 'services/api_service.dart';
import 'screens/server_list_screen.dart';

void main() async {
  // Ensure Flutter bindings are initialized (needed for SharedPreferences)
  WidgetsFlutterBinding.ensureInitialized();

  // Force dark status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Initialize services
  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs);
  final apiService = ApiService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ServerProvider(storageService, apiService)..loadServers(),
        ),
      ],
      child: const MediaStreamerApp(),
    ),
  );
}

class MediaStreamerApp extends StatelessWidget {
  const MediaStreamerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media Streamer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const ServerListScreen(),
    );
  }
}
