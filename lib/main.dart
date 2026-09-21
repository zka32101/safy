import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_theme.dart';
import 'features/onboarding/startup_gate.dart';
import 'firebase_options.dart';
import 'providers/localization_provider.dart'
    show localizationProvider, initializeLocalizationPreferences;
import 'widgets/offline_banner.dart';
import 'widgets/force_update_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // 業種一覧・招待コードの照会は参加/登録より前に行われ、Firestoreルールがログイン済みを
  // 要求するため、起動時に匿名ログインしておく。失敗しても起動は止めない
  // (登録時の EmployeeService._ensureAuthUid が再試行する)。
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (_) {}
  await initializeLocalizationPreferences();
  runApp(const ProviderScope(child: SafyApp()));
}

class SafyApp extends ConsumerWidget {
  const SafyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the localization provider to rebuild when locale changes
    final locale = ref.watch(localizationProvider);

    return MaterialApp(
      title: '安心企業研修Safy',

      // Localization configuration
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,

      // Theme configuration
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),

      // Builder to wrap the app with utility widgets
      builder: (context, child) => OfflineBanner(
        child: ForceUpdateGate(child: child ?? const SizedBox()),
      ),

      home: const StartupGate(),
    );
  }
}
