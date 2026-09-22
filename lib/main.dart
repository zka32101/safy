import 'dart:async';

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
import 'providers/service_providers.dart' show pushNotificationServiceProvider;
import 'services/secure_storage_service.dart';
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

  // runApp前(ProviderScope未構築)でもfirestoreProviderパターンを使えるよう、
  // ProviderContainerを先に作りUncontrolledProviderScopeでアプリに引き継ぐ。
  final container = ProviderContainer();
  // プッシュ通知のパーミッションリクエスト・FCMトークン登録は、既に企業へ参加済み
  // (companyIdが端末に保存済み)の場合のみ行う。未参加(オンボーディング前)の場合は
  // Employeeドキュメントがまだ無くトークンの保存先が無いため、
  // EmployeeService.joinViaInviteCode/createAdmin完了後の初回起動時に登録される。
  // 失敗しても起動は止めない(通知が使えないだけでアプリ自体は継続利用可能なため)。
  unawaited(_registerPushNotificationTokenIfJoined(container));

  runApp(UncontrolledProviderScope(container: container, child: const SafyApp()));
}

Future<void> _registerPushNotificationTokenIfJoined(ProviderContainer container) async {
  try {
    final companyId = await SecureStorageService.getCompanyId();
    final employeeId = FirebaseAuth.instance.currentUser?.uid;
    if (companyId == null || employeeId == null) return;
    await container.read(pushNotificationServiceProvider).registerToken(
          companyId: companyId,
          employeeId: employeeId,
        );
  } catch (_) {
    // 通知権限拒否・端末未対応等で失敗してもアプリ起動は継続する。
  }
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
