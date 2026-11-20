import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'providers/app_providers.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Cap image cache strictly for Redmi A2 (2–3 GB RAM) stability.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 20 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 50;

  runApp(const ProviderScope(child: MyakoApp()));
}

/// Root widget for Myako — Smart Lecture Notes.
class MyakoApp extends ConsumerWidget {
  const MyakoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Myako',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}
