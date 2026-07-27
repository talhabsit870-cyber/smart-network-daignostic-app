import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'home/home_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NetDiagnose',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bgBottom,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accentPrimary,
          secondary: AppColors.accentSecondary,
          surface: AppColors.surface,
          error: AppColors.coral,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: 1,
          ),
          titleMedium: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          bodyMedium: TextStyle(color: AppColors.textMuted, fontSize: 13),
          bodySmall: TextStyle(color: AppColors.textMuted, fontSize: 12),
          labelSmall: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentPrimary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.surfaceBorder,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.surfaceBorder),
            foregroundColor: AppColors.textPrimary,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bgTop,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
