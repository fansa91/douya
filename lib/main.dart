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
      builder: (context, _) => MaterialApp(
        title: 'douya',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: SettingsStore.instance.seedColor,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F5F0),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: SettingsStore.instance.seedColor,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: SettingsStore.instance.themeMode,
        home: AdaptiveScaffold(repository: repository),
      ),
    );
  }
}
