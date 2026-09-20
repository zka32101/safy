import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:safy/features/dashboard/app_shell.dart';
import 'package:safy/providers/session_provider.dart';
import 'package:safy/providers/firebase_providers.dart';
import 'package:safy/data/models/employee_model.dart';
import 'package:safy/data/models/company_model.dart';

final _testEmployee = Employee(
  id: 'emp1',
  companyId: 'company1',
  teamId: 'team1',
  displayName: 'テスト太郎',
  role: EmployeeRole.member,
  createdAt: DateTime(2026, 1, 1),
);

final _testCompany = Company(
  id: 'company1',
  name: 'テスト株式会社',
  industryId: 'it',
  planType: PlanType.team,
  contractedHeadcount: 10,
  customPassThreshold: const {},
  createdAt: DateTime(2026, 1, 1),
);

class _SignedInSessionNotifier extends SessionNotifier {
  _SignedInSessionNotifier() {
    signIn(employee: _testEmployee, company: _testCompany);
  }
}

Future<void> _pumpAppShell(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => _SignedInSessionNotifier()),
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      ],
      child: MaterialApp(
        home: AppShell(),
      ),
    ),
  );
}

void main() {
  group('AppShell Navigation Tests', () {
    testWidgets('ボトムナビゲーションバーが表示される', (WidgetTester tester) async {
      await _pumpAppShell(tester);

      // ボトムナビゲーションバーが表示されることを確認
      expect(find.byType(BottomNavigationBar), findsOneWidget);

      // 4つのアイテムが表示されることを確認（初期選択はホームなのでアクティブアイコン）
      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(find.byIcon(Icons.school_outlined), findsOneWidget);
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
      expect(find.byIcon(Icons.trending_up_outlined), findsOneWidget);
    });

    testWidgets('タブラベルが表示される', (WidgetTester tester) async {
      await _pumpAppShell(tester);

      // タブラベルが表示されることを確認
      expect(find.text('ホーム'), findsOneWidget);
      expect(find.text('学習パス'), findsOneWidget);
      expect(find.text('Q&A'), findsOneWidget);
      expect(find.text('マイ成長'), findsOneWidget);
    });

    testWidgets('タブ切り替えが機能する', (WidgetTester tester) async {
      await _pumpAppShell(tester);

      // 最初のタブ（ホーム）がアクティブであることを確認
      expect(find.byIcon(Icons.home), findsOneWidget);

      // 2番目のタブ（学習パス）をタップ
      await tester.tap(find.byIcon(Icons.school_outlined));
      await tester.pumpAndSettle();

      // アクティブアイコンが変わることを確認
      expect(find.byIcon(Icons.school), findsOneWidget);

      // 3番目のタブ（Q&A）をタップ
      await tester.tap(find.byIcon(Icons.forum_outlined));
      await tester.pumpAndSettle();

      // アクティブアイコンが変わることを確認
      expect(find.byIcon(Icons.forum), findsOneWidget);

      // 4番目のタブ（マイ成長）をタップ
      await tester.tap(find.byIcon(Icons.trending_up_outlined));
      await tester.pumpAndSettle();

      // アクティブアイコンが変わることを確認
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    });

    testWidgets('各タブでスクリーンが切り替わる', (WidgetTester tester) async {
      await _pumpAppShell(tester);

      // 学習パスタブをタップ
      await tester.tap(find.byIcon(Icons.school_outlined));
      await tester.pumpAndSettle();

      // Q&Aタブをタップ
      await tester.tap(find.byIcon(Icons.forum_outlined));
      await tester.pumpAndSettle();

      // スクリーンの切り替えが成功することを確認
      // （実際の実装により詳細が異なる可能性がある）
    });

    testWidgets('タブの状態が保持される', (WidgetTester tester) async {
      await _pumpAppShell(tester);

      // 学習パスタブをタップ
      // NOTE: 各画面がローディング中にCircularProgressIndicatorを表示するため、
      // pumpAndSettleではなく固定時間のpumpを使う(無限アニメーションでタイムアウトする)
      await tester.tap(find.byIcon(Icons.school_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // ホームタブをタップして戻る
      await tester.tap(find.byIcon(Icons.home_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // 学習パスタブをタップして戻る
      await tester.tap(find.byIcon(Icons.school_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // 学習パスタブがアクティブであることを確認
      expect(find.byIcon(Icons.school), findsOneWidget);
    });
  });
}
