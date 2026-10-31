import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'api/douban_client.dart';
import 'data/fake_repository.dart';
import 'data/repository.dart';
import 'data/settings.dart';
import 'ui/adaptive_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsStore.instance.init();
  runApp(const DouyaApp());
}

/// Repository selection, decided by whether keys were passed in:
///   keys present (--dart-define, e.g. the CI release build, whose
///     secrets feed them) -> RealDoubanRepository, live network data
///   keys absent (local run without --dart-define) -> FakeDoubanRepository,
///     offline sample data, no network calls
/// This is why the v0.1 Android APK never hit the network even though
/// INTERNET was already declared: it was hard-wired to Fake. From v0.2
/// on, a release build with keys actually uses the APIs it ships with.
class DouyaApp extends StatelessWidget {
  const DouyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final hasKeys = const String.fromEnvironment('DOUBAN_API_KEY').isNotEmpty &&
        const String.fromEnvironment('DOUBAN_API_SECRET').isNotEmpty;
    final DoubanRepository repository = hasKeys ? RealDoubanRepository(DoubanClient()) : const FakeDoubanRepository();
    return AnimatedBuilder(
      animation: SettingsStore.instance,
      builder: (context, _) => DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          final settings = SettingsStore.instance;
          // Dynamic color only exists where the OS provides it
          // (Android 12+); elsewhere the schemes are null and the
          // seed color is used, dynamic setting or not.
          final lightScheme = settings.dynamicColor && lightDynamic != null
              ? lightDynamic
              : ColorScheme.fromSeed(
                  seedColor: settings.seedColor,
                  brightness: Brightness.light,
                );
          final darkScheme = settings.dynamicColor && darkDynamic != null
              ? darkDynamic
              : ColorScheme.fromSeed(
                  seedColor: settings.seedColor,
                  brightness: Brightness.dark,
                );
          final useDynamic = settings.dynamicColor && lightDynamic != null;
          return MaterialApp(
            title: 'douya',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: lightScheme,
              // The paper background is douya's own look; it only
              // applies to the seed-color theme, not the dynamic one.
              scaffoldBackgroundColor: useDynamic ? null : const Color(0xFFF7F5F0),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: darkScheme,
              useMaterial3: true,
            ),
            themeMode: settings.themeMode,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(settings.fontScale),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
            home: AdaptiveScaffold(repository: repository),
          );
        },
      ),
    );
  }
}
