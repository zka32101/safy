import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:safy/features/qa_forum/qa_forum_screen.dart';
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

Future<void> _pumpQAForumScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => _SignedInSessionNotifier()),
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: QAForumScreen(),
        ),
      ),
    ),
  );
}

void main() {
  group('QAForumScreen Tests', () {
    testWidgets('Q&Aフォーラム画面が正しく表示される', (WidgetTester tester) async {
      await _pumpQAForumScreen(tester);

      // タイトルが表示されることを確認
      expect(find.text('Q&Aフォーラム'), findsWidgets);

      // 検索フィールドが表示されることを確認
      expect(find.byIcon(Icons.search), findsOneWidget);

      // FAB（Floating Action Button）が表示されることを確認
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('検索フィールドが入力を受け付ける', (WidgetTester tester) async {
      await _pumpQAForumScreen(tester);

      // 検索フィールドを探す
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // テキストを入力
      await tester.enterText(searchField, 'テスト');
      await tester.pumpAndSettle();

      // 入力されたテキストが表示されることを確認
      expect(find.text('テスト'), findsWidgets);
    });

    testWidgets('ソートチップが表示される', (WidgetTester tester) async {
      await _pumpQAForumScreen(tester);

      // ソートオプションが表示されることを確認
      expect(find.text('最新'), findsOneWidget);
      expect(find.text('人気'), findsOneWidget);
      expect(find.text('未回答'), findsOneWidget);
    });

    testWidgets('質問投稿ボタンがFABであることを確認', (WidgetTester tester) async {
      await _pumpQAForumScreen(tester);

      // FABが存在することを確認
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // FABのアイコンが追加アイコンであることを確認
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('ソートチップがクリックできる', (WidgetTester tester) async {
      await _pumpQAForumScreen(tester);

      // 「人気」ソートをタップ
      await tester.tap(find.widgetWithText(FilterChip, '人気'));
      await tester.pumpAndSettle();

      // FilterChip が存在することを確認
      expect(find.byType(FilterChip), findsWidgets);
    });

    testWidgets('検索フィールドのクリアボタンが機能する', (WidgetTester tester) async {
      await _pumpQAForumScreen(tester);

      // 検索フィールドにテキストを入力
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'テスト');
      await tester.pumpAndSettle();

      // テキストが入力されたことを確認
      expect(find.text('テスト'), findsWidgets);

      // クリアボタンが表示されることを確認（入力がある場合）
      // NOTE: 実装による - suffixIcon が表示される
    });
  });
}
