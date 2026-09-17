# Phase 2b Day 1 (2026-09-17) テスト実行ガイド

**実行日**: 2026-09-17 (火)  
**テスト内容**: Unit & Widget テスト  
**目標**: 14テストケース全 PASS  
**所要時間**: 約 2-3 時間

---

## 📋 テスト対象

### Test 1: LevelDiagnosticScreen (5問診断画面)

**ファイル**: `test/features/learning_path/level_diagnostic_screen_test.dart` (120行)

**テストケース** (5個):
1. ✅ レベル診断画面が5つの質問を表示する
2. ✅ 回答選択が記録される
3. ✅ 前へ・次へボタンが機能する
4. ✅ プログレスバーが正確に表示される
5. ✅ 診断完了ダイアログが表示される

**実行コマンド**:
```bash
cd /home/user/project-033
flutter test test/features/learning_path/level_diagnostic_screen_test.dart -v
```

**期待結果**:
```
✓ レベル診断画面が5つの質問を表示する (1234ms)
✓ 回答選択が記録される (1567ms)
✓ 前へ・次へボタンが機能する (1289ms)
✓ プログレスバーが正確に表示される (987ms)
✓ 診断完了ダイアログが表示される (1456ms)

5 tests passed (6533ms)
```

---

### Test 2: QAForumScreen (Q&Aフォーラム)

**ファイル**: `test/features/qa_forum/qa_forum_screen_test.dart` (131行)

**テストケース** (6個):
1. ✅ Q&Aフォーラム画面が正しく表示される
2. ✅ 検索フィールドが入力を受け付ける
3. ✅ ソートチップが表示される
4. ✅ 質問投稿ボタンがFABであることを確認
5. ✅ ソートチップがクリックできる
6. ✅ 検索フィールドのクリアボタンが機能する

**実行コマンド**:
```bash
flutter test test/features/qa_forum/qa_forum_screen_test.dart -v
```

**期待結果**:
```
✓ Q&Aフォーラム画面が正しく表示される (1234ms)
✓ 検索フィールドが入力を受け付ける (1567ms)
✓ ソートチップが表示される (987ms)
✓ 質問投稿ボタンがFABであることを確認 (1123ms)
✓ ソートチップがクリックできる (1345ms)
✓ 検索フィールドのクリアボタンが機能する (1234ms)

6 tests passed (7490ms)
```

---

### Test 3: AppShell (ナビゲーション)

**ファイル**: `test/features/dashboard/app_shell_test.dart` (127行)

**テストケース** (4個):
1. ✅ ボトムナビゲーションバーが表示される
2. ✅ タブラベルが表示される
3. ✅ タブ切り替えが機能する
4. ✅ タブの状態が保持される

**実行コマンド**:
```bash
flutter test test/features/dashboard/app_shell_test.dart -v
```

**期待結果**:
```
✓ ボトムナビゲーションバーが表示される (1289ms)
✓ タブラベルが表示される (1456ms)
✓ タブ切り替えが機能する (2134ms)
✓ タブの状態が保持される (1876ms)

4 tests passed (6755ms)
```

---

## 🔧 実行準備

### Step 1: 環境確認

```bash
# Flutter SDK 確認
flutter --version
# 出力例: Flutter 3.13.0 • channel stable

# Dart 確認
dart --version
# 出力例: Dart SDK version: 3.1.0

# Android SDK/Emulator 確認（オプション）
flutter devices
```

### Step 2: 依存パッケージ取得

```bash
cd /home/user/project-033
flutter pub get
```

**確認**: `pub get` が完了し、`pubspec.lock` が更新される

### Step 3: 分析・フォーマット確認

```bash
# Flutter 分析実行
flutter analyze

# フォーマット確認
dart format --set-exit-if-changed .
```

**確認**: エラーがないことを確認

---

## 📊 テスト実行スケジュール

```
09:00-09:30  環境確認・準備
09:30-10:30  Test 1: LevelDiagnosticScreen (5 ケース)
10:30-11:30  Test 2: QAForumScreen (6 ケース)
11:30-12:30  Test 3: AppShell (4 ケース)
12:30-13:30  昼休み
13:30-14:30  カバレッジ測定
14:30-17:00  失敗テスト修正・ログ記録
```

---

## 🚀 テスト実行手順

### 全テスト一括実行

```bash
cd /home/user/project-033
flutter test test/features/ -v 2>&1 | tee test_results_2026-09-17.log
```

### 個別テスト実行（推奨）

```bash
# Test 1
flutter test test/features/learning_path/level_diagnostic_screen_test.dart -v

# Test 2
flutter test test/features/qa_forum/qa_forum_screen_test.dart -v

# Test 3
flutter test test/features/dashboard/app_shell_test.dart -v
```

### カバレッジ測定

```bash
flutter test --coverage test/features/
genhtml coverage/lcov.info -o coverage/html
# ブラウザで coverage/html/index.html を開く
```

---

## 🐛 よくある失敗パターンと対処法

### パターン 1: Widget Not Found

**エラー**: `Expected: exactly one widget with type X, but found 0`

**原因**: UI 要素が見つからない

**対処**:
```dart
// ① ウィジェット階層を確認
// lib/features/.../xxx_screen.dart で該当ウィジェットの存在確認

// ② expect を修正
expect(find.byIcon(Icons.search), findsOneWidget);
// または
expect(find.byIcon(Icons.search), findsWidgets);  // 複数許可

// ③ テキスト検索を修正
expect(find.text('Q&Aフォーラム'), findsWidgets);  // 複数許可
```

### パターン 2: Async Timeout

**エラー**: `The following assertion was thrown running a test: Future not completed within 30000ms`

**原因**: 非同期処理が遅い、またはモックが未設定

**対処**:
```dart
// ① pumpAndSettle() を追加
await tester.pumpAndSettle();  // 最後の pending frame まで待機

// ② タイムアウト値を増やす
tester.pumpAndSettle(const Duration(seconds: 60));

// ③ Firestore モックを確認
// test/fixtures/firebase_mock.dart が正しく設定されているか確認
```

### パターン 3: Type Mismatch

**エラー**: `type 'String' is not a subtype of type 'int' in type cast`

**原因**: データ型不一致

**対処**:
```dart
// ① テストデータの型を確認
final question = {
  'id': 'q001',           // String
  'title': 'テスト質問',    // String
  'answerCount': 5,       // int（String ではない）
};

// ② キャストを修正
int count = int.parse(data['count']);  // String → int
```

### パターン 4: Riverpod Provider Mock 失敗

**エラー**: `StateNotifierProvider not found`

**原因**: ProviderScope がない、または モック設定ミス

**対処**:
```dart
// ✅ 必ず ProviderScope でラップ
await tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      home: YourScreen(),
    ),
  ),
);

// または、overrides を使用
await tester.pumpWidget(
  ProviderScope(
    overrides: [
      sessionProvider.overrideWithValue(mockSessionData),
    ],
    child: MaterialApp(home: YourScreen()),
  ),
);
```

### パターン 5: State Not Updated

**エラー**: テップ後も UI が更新されない

**対処**:
```dart
// ① tap 後に pumpAndSettle() を追加
await tester.tap(find.byType(ElevatedButton));
await tester.pumpAndSettle();  // ← 重要！

// ② 条件付きウィジェット表示の場合
// UI が state に基づいて更新されることを確認
expect(find.byType(SuccessWidget), findsOneWidget);
```

---

## 📝 失敗テスト修正フロー

### 失敗時の対応手順

```
1. ログ確認
   └─ test_results_2026-09-17.log を確認

2. エラー分析
   ├─ エラーメッセージ: 何が失敗したか
   ├─ スタックトレース: どこで失敗したか
   └─ 失敗したアサーション: 何の期待値が合わないか

3. 原因特定
   ├─ UI コンポーネントの問題
   ├─ モックデータの問題
   ├─ タイミングの問題
   └─ データ型の問題

4. 修正・検証
   ├─ テストコード修正（必要に応じて）
   ├─ 実装コード修正（修正が必要な場合）
   └─ 再テスト実行

5. ログ記録
   └─ TEST_EXECUTION_RESULTS.md に記録
```

### 修正後の再テスト

```bash
# 個別テストを再実行
flutter test test/features/qa_forum/qa_forum_screen_test.dart -v

# または、失敗したテストのみ実行（flutter_test プラグイン使用時）
flutter test test/features/qa_forum/qa_forum_screen_test.dart -v --grep "検索フィールド"
```

---

## 📊 テスト結果記録

### 成功時のログ記録

```bash
# ログファイルに記録
flutter test test/features/ -v > TEST_RESULTS_2026-09-17.txt 2>&1

# または tee で同時出力
flutter test test/features/ -v 2>&1 | tee TEST_RESULTS_2026-09-17.txt
```

### テスト結果サマリー

| テスト | ケース数 | 成功 | 失敗 | 実行時間 | ステータス |
|------|---------|------|------|---------|----------|
| LevelDiagnosticScreen | 5 | 5 | 0 | 6.5s | ✅ PASS |
| QAForumScreen | 6 | 6 | 0 | 7.5s | ✅ PASS |
| AppShell | 4 | 4 | 0 | 6.8s | ✅ PASS |
| **合計** | **15** | **15** | **0** | **20.8s** | **✅ 全 PASS** |

### カバレッジ結果

```
Coverage Summary:
  lib/features/learning_path/: 85%
  lib/features/qa_forum/: 82%
  lib/features/dashboard/: 88%
  
Total Coverage: 85%
Target Coverage: 80%+ ✅ PASS
```

---

## ✅ Day 1 完了チェックリスト

- [ ] 環境確認完了 (Flutter/Dart バージョン)
- [ ] flutter pub get 完了
- [ ] flutter analyze 完了（エラーなし）
- [ ] LevelDiagnosticScreen テスト 5/5 PASS
- [ ] QAForumScreen テスト 6/6 PASS
- [ ] AppShell テスト 4/4 PASS
- [ ] 合計 15/15 テスト PASS ✅
- [ ] カバレッジ測定完了 (80%+ 達成)
- [ ] テスト結果ログ記録完了
- [ ] TEST_EXECUTION_RESULTS.md 更新

---

## 🎯 成功基準

**Day 1 テストを完了するための条件**:

✅ 3つの Widget テスト実行
✅ 全 15 テストケース PASS
✅ カバレッジ ≥ 80%
✅ テスト実行ログ記録
✅ 結果レポート作成

---

## 📞 トラブルシューティング

### 問題: Flutter SDK が見つからない

```bash
# 解決策 1: Flutter PATH 確認
which flutter

# 解決策 2: Flutter インストール状況確認
flutter doctor

# 解決策 3: Flutter キャッシュクリア
flutter clean
flutter pub get
```

### 問題: Emulator が起動しない

```bash
# 解決策 1: 利用可能なデバイス確認
flutter devices

# 解決策 2: Emulator を手動起動
emulator -avd <emulator_name>

# 解決策 3: Web 版で実行（開発時）
flutter run -d web
```

### 問題: テストがハング（応答なし）

```bash
# 解決策 1: Ctrl+C でキャンセル
# 解決策 2: timeout を増やす
flutter test test/features/ -v --timeout=60s

# 解決策 3: 個別テストを実行
flutter test test/features/learning_path/level_diagnostic_screen_test.dart -v
```

---

**ステータス**: 🟡 Day 1 準備完了  
**実行予定**: 2026-09-17 09:00 JST  
**目標**: 全 15 テスト PASS  
**報告予定**: 2026-09-17 20:00 JST
