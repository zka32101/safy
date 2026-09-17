# Phase 2b テスト実行 週間スケジュール

**期間**: 2026-09-17 ~ 2026-09-23（7日間）  
**目標**: テスト完全終了 → 本番デプロイ準備  
**ステータス**: 🟡 テスト実行中

---

## 📅 週間タイムライン

```
Day 1 (09/17)  Unit & Widget Tests           ┌─────────┐
Day 2 (09/18)  Unit & Widget Tests 続行      │ Week 1  │
Day 3 (09/19)  統合テスト                    ├─────────┤
Day 4 (09/20)  UI/UX & パフォーマンステスト │ Week 2  │
Day 5 (09/21)  セキュリティ & リグレッション│         │
Day 6 (09/22)  最終確認 & ドキュメント      └─────────┘
Day 7 (09/23)  本番デプロイ
```

---

## 📋 Day 1: 2026-09-17（火）- Unit & Widget Tests

**目標**: 3 つの Widget テスト PASS

### テスト対象

1. **LevelDiagnosticScreen** (5問診断画面)
   - 質問表示（5問）
   - 回答記録
   - プログレスバー
   - 診断完了ダイアログ

2. **QAForumScreen** (Q&A フォーラム)
   - 質問一覧表示
   - 検索機能
   - ソート機能（最新・人気・未回答）
   - 投稿ボタン（FAB）

3. **AppShell** (ナビゲーション)
   - 4タブ表示
   - タブ切り替え
   - 画面状態保持
   - Riverpod 統合

### 実行手順

```bash
# テスト実行
flutter test test/features/learning_path/level_diagnostic_screen_test.dart -v
flutter test test/features/qa_forum/qa_forum_screen_test.dart -v
flutter test test/features/dashboard/app_shell_test.dart -v

# カバレッジ測定
flutter test --coverage test/features/
```

### 完了条件

- ✅ 15個のテストケース全て PASS
- ✅ カバレッジ ≥ 50%
- ✅ テストログ記録

### 失敗時の対応

| テスト | 失敗原因の可能性 | 対処 |
|------|---------------|------|
| Widget not found | UI レイアウト変更 | ウィジェット階層確認 |
| Async timeout | Cloud Functions モック失敗 | Firestore モック設定確認 |
| Type error | データ型不一致 | 型定義確認 |

---

## 📋 Day 2: 2026-09-18（水）- Unit & Widget Tests 続行

**目標**: 失敗テストの修正・全テスト PASS

### 実行内容

1. **Day 1 失敗テストの分析**
   - エラーログ確認
   - 原因特定
   - 修正案立案

2. **コード修正**
   - テストコード修正（必要に応じて）
   - 実装コード修正
   - モック設定修正

3. **再テスト実行**
   ```bash
   # 失敗したテストのみ再実行
   flutter test [failed-test-file] -v
   
   # 全テスト再実行
   flutter test test/features/ -v
   ```

4. **修正コミット**
   ```bash
   git add .
   git commit -m "修正: [テスト失敗原因] テスト PASS"
   git push origin claude/phase2b-learning-paths
   ```

### 完了条件

- ✅ 全 Widget テスト PASS
- ✅ カバレッジ ≥ 60%
- ✅ 修正コード commit 完了

---

## 📋 Day 3: 2026-09-19（木）- 統合テスト

**目標**: エンドツーエンド フロー検証

### テスト項目

1. **診断 → 学習パス フロー**
   ```
   LevelDiagnosticScreen
     ↓ (5問回答)
   completeLevelDiagnostic (Cloud Function)
     ↓ (結果保存)
   LearningPathScreen
     ↓ (レベル別パス表示)
   ```
   - **検証**: 診断結果が学習パスに反映されるか

2. **Q&A フォーラム フロー**
   ```
   QAForumScreen
     ↓ (質問投稿)
   submitQuestion (Cloud Function)
     ↓ (Firestore 保存)
   リアルタイム更新
     ↓ (answer リスナー)
   QuestionDetailScreen
   ```
   - **検証**: 質問投稿からリアルタイム表示まで

3. **ナビゲーション フロー**
   ```
   HomeScreen → AppShell
   AppShell (4タブ)
     ↓ (タブ切り替え)
   各画面（状態保持確認）
   ```
   - **検証**: 状態が消えないか、画面切り替えが正常か

### 実行手順

```bash
# 統合テスト実行
flutter test test/features/ -v --tags integration

# または個別に実行
flutter drive --target=test_driver/app.dart
```

### 完了条件

- ✅ 3つの主要フロー PASS
- ✅ リアルタイム更新 動作確認
- ✅ Firestore 連携 検証完了

---

## 📋 Day 4: 2026-09-20（金）- UI/UX & パフォーマンステスト

**目標**: ユーザー体験の品質検証・性能確認

### UI/UX テスト

| テスト項目 | 期待結果 | チェック内容 |
|----------|--------|----------|
| レイアウト | オーバーフローなし | 全画面サイズで表示確認 |
| テキスト可読性 | 十分な大きさ・コントラスト | フォント・色確認 |
| ボタン反応 | 100ms 以内 | タップ反応速度 |
| エラーメッセージ | わかりやすい日本語 | 内容確認 |
| ダークモード | 対応している | 両モード確認 |

### パフォーマンステスト

```bash
# パフォーマンス測定
flutter test test/features/ --profile

# メモリ使用量監視
flutter run --profile
# -> DevTools で Memory タブ確認
```

| 項目 | ターゲット | 判定基準 |
|-----|----------|--------|
| アプリ起動時間 | < 3秒 | 計測 |
| 質問一覧読み込み | < 2秒 | Firestore Stream |
| 診断完了反応 | < 1秒 | API 呼び出し |
| メモリ使用量 | < 100MB | DevTools |
| メモリリーク | なし | 継続監視 |

### 完了条件

- ✅ UI/UX チェックリスト完成
- ✅ パフォーマンス測定完了
- ✅ 改善提案あればチケット作成

---

## 📋 Day 5: 2026-09-21（土）- セキュリティ & リグレッション テスト

**目標**: セキュリティ脆弱性なし・既存機能破損なし

### セキュリティテスト

#### アクセス制御

| テスト | 期待結果 | 実施方法 |
|------|--------|--------|
| ログインなしアクセス | 拒否される | auth チェック確認 |
| 他社データ表示 | 拒否される | companyId フィルタ確認 |
| 権限なし操作 | 拒否される | employeeId 検証確認 |

#### 入力値検証

```bash
# 各フィールドの制限を確認
- 質問タイトル: 200文字制限
- 質問説明: 1000文字制限
- 回答内容: 2000文字制限

# 境界値テスト
- 正確な文字数でテスト（199, 200, 201等）
- 特殊文字・絵文字テスト
- SQL インジェクション試行テスト
```

#### レート制限

```bash
# 5分間隔制限を確認
1. 質問投稿
2. 5分以内に再投稿 → エラー期待
3. 5分後に投稿 → 成功期待
```

### リグレッション テスト

既存機能の破損確認：

- [ ] ホーム画面 表示・操作正常
- [ ] モジュール学習 学習・進捗記録正常
- [ ] マイ成長 統計表示正常
- [ ] ログイン・ログアウト 認証フロー正常
- [ ] Phase 1 Tier 1 Training 動作正常
- [ ] Phase 2a Dashboard 動作正常

### 完了条件

- ✅ セキュリティテスト PASS
- ✅ リグレッション テスト PASS
- ✅ セキュリティ問題なし

---

## 📋 Day 6: 2026-09-22（日）- 最終確認 & ドキュメント

**目標**: 本番デプロイ前の全項目確認

### 最終チェックリスト

#### テスト完了確認

- [ ] ユニット・ウィジェットテスト: PASS ✅
- [ ] 統合テスト: PASS ✅
- [ ] UI/UX テスト: PASS ✅
- [ ] パフォーマンステスト: ターゲット達成 ✅
- [ ] セキュリティテスト: PASS ✅
- [ ] リグレッション テスト: PASS ✅

#### テストカバレッジ

- [ ] 総カバレッジ ≥ 80% → 現在: ___%
- [ ] 各機能カバレッジ ≥ 80%
  - [ ] LevelDiagnosticScreen: ___% (target 85%)
  - [ ] QAForumScreen: ___% (target 85%)
  - [ ] Cloud Functions: ___% (target 90%)

#### ドキュメント完成

- [ ] ユーザーガイド作成
  - [ ] Q&A フォーラムの使い方
  - [ ] 学習パスの見方
  - [ ] よくある質問

- [ ] リリースノート作成
  - [ ] 新機能説明
  - [ ] 改善項目
  - [ ] 既知の問題（あれば）

- [ ] 管理者向けドキュメント
  - [ ] Firestore セキュリティルール
  - [ ] Cloud Functions の監視
  - [ ] トラブルシューティング

#### 本番準備

- [ ] Firestore セキュリティルール確認
  ```bash
  firebase deploy --only firestore:rules --dry-run
  ```

- [ ] Cloud Functions ビルド確認
  ```bash
  cd functions
  npm run build
  npm test
  ```

- [ ] 本番前バックアップ実施
  ```bash
  # Firestore データのバックアップ確認
  ```

- [ ] ロールバック手順確認
  - [ ] 前バージョン保存
  - [ ] 復旧手順書作成

- [ ] ユーザー通知準備
  - [ ] メール文作成
  - [ ] 送信リスト確認

### 完了条件

- ✅ テスト 90%+ PASS
- ✅ ドキュメント完成
- ✅ 本番環境チェック完了
- ✅ デプロイ前チェックリスト完成

---

## 🚀 Day 7: 2026-09-23（月）- 本番デプロイ

**目標**: 本番環境へのデプロイ・24時間監視

### デプロイ手順

```bash
# 1. バックアップ実施
firebase firestore:export gs://[bucket]/backup-2026-09-23

# 2. Firestore ルール更新
firebase deploy --only firestore:rules

# 3. Cloud Functions デプロイ
firebase deploy --only functions

# 4. Flutter アプリ デプロイ
# iOS: App Store Connect へ submit
# Android: Google Play Console へ submit
```

### デプロイ後監視（24時間）

| 項目 | 目標 | チェック |
|-----|------|--------|
| エラー率 | < 1% | ログ監視 |
| レスポンス時間 | < 2s | パフォーマンス監視 |
| セキュリティ | 問題なし | セキュリティ監視 |
| ユーザー反応 | 満足度 > 4/5 | フィードバック確認 |

### 完了条件

- ✅ デプロイ成功
- ✅ 24時間監視完了
- ✅ ユーザー反応良好

---

## 📊 テスト結果サマリー

### 日別進捗

| 日付 | テスト種別 | 目標 | 結果 | ステータス |
|-----|---------|------|------|----------|
| 09/17 | Unit & Widget | 15 PASS | -- | 🟡 実施中 |
| 09/18 | 修正・再テスト | 15 PASS | -- | ⬜ 予定中 |
| 09/19 | 統合テスト | 3 PASS | -- | ⬜ 予定中 |
| 09/20 | UI/UX・パフォーマンス | 達成 | -- | ⬜ 予定中 |
| 09/21 | セキュリティ・リグレッション | PASS | -- | ⬜ 予定中 |
| 09/22 | 最終確認 | 完成 | -- | ⬜ 予定中 |
| 09/23 | 本番デプロイ | 成功 | -- | ⬜ 予定中 |

### テストカバレッジ進捗

```
Day 1 ████░░░░░░ 40% (目標: 50%)
Day 2 ██████░░░░ 60% (目標: 80%)
Day 6 ████████░░ 80%+ (目標: 80%+)
```

---

## ⚠️ リスク管理

### High Priority Risks

| リスク | 影響度 | 対策 |
|------|------|------|
| Firestore ルールデプロイ失敗 | Critical | 事前テスト・Dry-run 実施 |
| Cloud Functions ビルド失敗 | Critical | ローカルビルドテスト |
| テスト大量失敗 | High | Day 1-2 で集中対応 |

### Mitigation Plan

1. **デイリー報告**
   - 朝: 前日の進捗報告
   - 夜: 本日の完了項目報告

2. **早期警告**
   - 失敗テストは即日対応
   - ブロッカーは Day 2 中に解決

3. **バックアップ体制**
   - 毎日 Firestore バックアップ
   - 本番前フルバックアップ

---

## 📞 サポート連絡先

### 問題発生時

- テスト失敗: TEST_EXECUTION_GUIDE.md 参照
- セキュリティ問題: SECURITY_REVIEW_PHASE2B.md 確認
- デプロイ問題: PRODUCTION_CHECKLIST.md 手順確認

### ドキュメント

- TEST_PLAN_PHASE2B.md - 全テスト計画
- TESTING_DAY1_CHECKLIST.md - 本日チェックリスト
- SECURITY_REVIEW_PHASE2B.md - セキュリティ詳細
- PRODUCTION_CHECKLIST.md - 本番デプロイ

---

**ステータス**: 🟡 Day 1 実施中  
**最終更新**: 2026-09-17  
**次の更新**: 毎日 17:00 JST（進捗報告）

