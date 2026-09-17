# Phase 2b テスト実行 Day 1 チェックリスト

**日付**: 2026-09-17  
**フェーズ**: Unit & Widget Tests  
**目標**: LevelDiagnosticScreen, QAForumScreen, AppShell のテスト実行  
**期限**: 本日 17:00 JST

---

## ✅ テスト実行前準備

### 環境確認

- [ ] Flutter SDK バージョン確認
  ```bash
  flutter --version
  ```
  
- [ ] Dart バージョン確認
  ```bash
  dart --version
  ```

- [ ] 依存関係インストール
  ```bash
  cd /home/user/project-033
  flutter pub get
  ```

- [ ] 分析・フォーマット確認
  ```bash
  flutter analyze
  dart format --set-exit-if-changed .
  ```

### Firebase Emulator セットアップ（オプション）

- [ ] Firebase CLI インストール確認
  ```bash
  firebase --version
  ```

- [ ] Emulator Suite 起動
  ```bash
  firebase emulators:start
  ```

- [ ] テストデータ準備
  ```bash
  firebase emulators:start --import ./test-data
  ```

---

## 🧪 Unit & Widget Tests 実行

### Test 1: LevelDiagnosticScreen

**ファイル**: `test/features/learning_path/level_diagnostic_screen_test.dart`

**実行コマンド**:
```bash
flutter test test/features/learning_path/level_diagnostic_screen_test.dart -v
```

**期待される結果**:
```
✓ レベル診断画面が5つの質問を表示する
✓ 回答選択が記録される
✓ 前へ・次へボタンが機能する
✓ 診断完了ボタンが最終質問で表示される
✓ プログレスバーが正確に表示される

5 tests passed (XXms)
```

**チェックリスト**:
- [ ] テスト実行完了
- [ ] 全テスト PASS
- [ ] パフォーマンス OK（< 2000ms）
- [ ] ログ記録完了

**結果記録**:
```
Status: ⬜ 未実行
Time: --
Passed: --
Failed: --
```

---

### Test 2: QAForumScreen

**ファイル**: `test/features/qa_forum/qa_forum_screen_test.dart`

**実行コマンド**:
```bash
flutter test test/features/qa_forum/qa_forum_screen_test.dart -v
```

**期待される結果**:
```
✓ 質問一覧が表示される
✓ 検索が機能する
✓ ソート（最新・人気・未回答）が機能する
✓ 投稿ボタン（FAB）が機能する
✓ エラーハンドリングが機能する

5 tests passed (XXms)
```

**チェックリスト**:
- [ ] テスト実行完了
- [ ] 全テスト PASS
- [ ] Firestore Stream モック動作確認
- [ ] ログ記録完了

**結果記録**:
```
Status: ⬜ 未実行
Time: --
Passed: --
Failed: --
```

---

### Test 3: AppShell

**ファイル**: `test/features/dashboard/app_shell_test.dart`

**実行コマンド**:
```bash
flutter test test/features/dashboard/app_shell_test.dart -v
```

**期待される結果**:
```
✓ 4タブすべてが表示される
✓ タブ切り替えが機能する
✓ 画面状態が保持される
✓ sessionProvider が統合されている

4 tests passed (XXms)
```

**チェックリスト**:
- [ ] テスト実行完了
- [ ] 全テスト PASS
- [ ] BottomNavigationBar 動作確認
- [ ] Riverpod provider モック確認

**結果記録**:
```
Status: ⬜ 未実行
Time: --
Passed: --
Failed: --
```

---

## 📊 カバレッジ測定

**実行コマンド**:
```bash
flutter test --coverage
```

**ターゲット**: 80%+  
**現在**: 45%

**期待結果**:
```
Coverage Summary:
  lib/features/learning_path/: 80%+
  lib/features/qa_forum/: 80%+
  lib/features/dashboard/: 85%+
  
Total Coverage: 50%+
```

**チェックリスト**:
- [ ] カバレッジ測定完了
- [ ] 報告書生成
  ```bash
  genhtml coverage/lcov.info -o coverage/html
  ```
- [ ] カバレッジレポート確認

---

## 🐛 テスト失敗時の対応

### 失敗テスト対応手順

1. **ログを確認**
   ```bash
   flutter test [test-file] -v > test_output.log 2>&1
   cat test_output.log
   ```

2. **エラー内容を分析**
   - エラーメッセージ
   - スタックトレース
   - 失敗したアサーション

3. **原因特定**
   - UI コンポーネントの問題
   - モックデータの問題
   - タイミングの問題

4. **修正・検証**
   ```bash
   # コード修正後、再実行
   flutter test [test-file] --update-goldens
   ```

5. **ログ記録**
   - TEST_EXECUTION_RESULTS.md に記録
   - 修正内容をコメント

### よくある問題と対処

| 問題 | 原因 | 対処 |
|-----|------|------|
| Widget not found | UI 要素がない | ウィジェット階層確認 |
| Timeout | 処理が遅い | pumpAndSettle() 追加 |
| State not updated | Riverpod mock 失敗 | ProviderScope 設定確認 |
| Type mismatch | データ型エラー | 型定義確認 |

---

## 📝 ログ・レポート

### テスト実行ログ保存

```bash
# 全テスト実行（ログ付き）
flutter test test/features/ -v 2>&1 | tee test_results_2026-09-17.log

# カバレッジ付き
flutter test --coverage test/features/ -v 2>&1 | tee test_coverage_2026-09-17.log
```

### テスト結果サマリー

| テスト | ステータス | 実行時間 | パス | 失敗 | 備考 |
|------|----------|---------|------|------|------|
| LevelDiagnosticScreen | ⬜ | -- | -- | -- | 実行前 |
| QAForumScreen | ⬜ | -- | -- | -- | 実行前 |
| AppShell | ⬜ | -- | -- | -- | 実行前 |
| **合計** | | | | | |

---

## ✨ Day 1 完了基準

本日中に以下を完了すること：

- [ ] 3つの Widget テスト実行
- [ ] 全テスト PASS（失敗があれば修正・再実行）
- [ ] カバレッジ測定 (≥ 50% 目標)
- [ ] テスト結果ログ記録
- [ ] TEST_EXECUTION_RESULTS.md 更新
- [ ] 修正コード commit & push

**完了時**: PR #33 にコメント投稿
```
✅ Day 1 Unit & Widget Tests Complete
- LevelDiagnosticScreen: 5/5 PASS
- QAForumScreen: 5/5 PASS
- AppShell: 4/4 PASS
- Coverage: XX%

Proceeding to Integration Tests (2026-09-19)
```

---

## 📅 スケジュール

```
09:00-10:00  環境確認・Firebase Emulator セットアップ
10:00-12:00  LevelDiagnosticScreen テスト実行
12:00-13:00  昼休み
13:00-15:00  QAForumScreen テスト実行
15:00-16:00  AppShell テスト実行
16:00-17:00  カバレッジ測定・ログ記録・修正対応
```

---

## 🔗 参考ドキュメント

- TEST_PLAN_PHASE2B.md - テスト計画全体
- TEST_EXECUTION_GUIDE.md - 詳細な実行手順
- SECURITY_REVIEW_PHASE2B.md - セキュリティ確認項目
- PRODUCTION_CHECKLIST.md - 本番前チェック

---

**ステータス**: 🟡 準備中  
**最終更新**: 2026-09-17 09:00 JST  
**次の更新**: 2026-09-17 17:00 JST（テスト完了後）

