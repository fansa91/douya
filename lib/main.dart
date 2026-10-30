import 'package:flutter/material.dart';

import 'data/fake_repository.dart';
import 'data/repository.dart';
import 'data/settings.dart';
import 'ui/adaptive_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsStore.instance.init();
  runApp(const DouyaApp());
}

/// Switch the repository here to go from UI skeleton to live data:
///   FakeDoubanRepository()  -> runs offline, no key needed
///   RealDoubanRepository(DoubanClient()) -> needs --dart-define keys
///     (and re-adding: import 'api/douban_client.dart';)
class DouyaApp extends StatelessWidget {
  const DouyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const DoubanRepository repository = FakeDoubanRepository();
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
        home: const AdaptiveScaffold(repository: repository),
      ),
    );
  }
}
