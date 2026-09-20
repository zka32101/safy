import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safy/main.dart';
import 'package:safy/providers/localization_provider.dart';

void main() {
  testWidgets('初回起動時はオンボーディングが表示される', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeLocalizationPreferences();

    await tester.pumpWidget(const ProviderScope(child: SafyApp()));
    await tester.pumpAndSettle();

    expect(find.text('業種に合わせて自動で優先度を提案'), findsOneWidget);
  });

  testWidgets('オンボーディング完了済みなら招待コード入力画面が表示される', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await initializeLocalizationPreferences();

    await tester.pumpWidget(const ProviderScope(child: SafyApp()));
    await tester.pumpAndSettle();

    expect(find.text('チームIDで参加する'), findsOneWidget);
    expect(find.text('個人で始める'), findsOneWidget);
  });
}
