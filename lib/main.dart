import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'features/home/hospital_finder_page.dart';
import 'theme/app_palette.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  // Fire-and-forget; ad widgets wait on their own load callbacks, so the UI
  // does not need to block on SDK initialization.
  unawaited(MobileAds.instance.initialize());
  runApp(const FindHospitalApp());
}

class FindHospitalApp extends StatelessWidget {
  const FindHospitalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.brand,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppPalette.brand,
          surface: AppPalette.surface,
          onSurface: AppPalette.ink,
        );

    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppPalette.bg,
      splashFactory: InkSparkle.splashFactory,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '전문의 병원 지도',
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(
          bodyColor: AppPalette.ink,
          displayColor: AppPalette.ink,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppPalette.ink,
          contentTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppPalette.surface,
          selectedColor: AppPalette.brand,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppPalette.ink,
          ),
          secondaryLabelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: const BorderSide(color: AppPalette.line),
          ),
          side: BorderSide.none,
        ),
      ),
      home: const HospitalFinderPage(),
    );
  }
}
