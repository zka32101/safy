# Tier 1 Training 運用ガイド

**学習期間**: 2026年9月16日(木) 09:00 JST ～ 2026年9月22日(水) 23:59 JST  
**対象**: 全42名 FTE（全企業対象）  
**目標**: 全4モジュール×80%以上の合格率達成

---

## 1. 事前準備チェックリスト（Sep 15 18:00 までに完了）

### インフラストラクチャ
- [ ] Firestore 容量確認（同時接続 100+ に対応可能か）
- [ ] Cloud Functions メモリ割当確認（512MB 以上）
- [ ] Cloud Logging アラート有効化
- [ ] Cloud Monitoring ダッシュボード作成
- [ ] Firebase Authentication 認証状態確認

### モジュール・コンテンツ
- [ ] 4つの Tier 1 Training モジュール Firestore 登録確認
- [ ] レッスン 16 個（4×4）登録確認
- [ ] クイズ問題 20 問（5×4）登録確認
- [ ] 各モジュール 80% 合格基準の確認

### Flutter アプリ
- [ ] TrainingDashboardScreen 動作確認
- [ ] モジュール表示・進捗トラッキング確認
- [ ] Sep 22 23:59 JST 期限カウントダウン確認
- [ ] 修了証発行ロジック確認

### Cloud Functions
- [ ] recordTrainingProgress 関数デプロイ確認
- [ ] issueTrainingCertificate 関数デプロイ確認
- [ ] checkTrainingDeadline 関数デプロイ確認
- [ ] エラーハンドリング・リトライロジック確認

### 通知・コミュニケーション
- [ ] FCM プッシュ通知設定確認
- [ ] Slack 通知チャネル #tier1-training 作成
- [ ] 管理者・運用チーム通知設定確認
- [ ] 学習者向けメール通知テンプレート確認

### ステージング環境テスト
- [ ] 全フローE2E テスト実施（5名以上でテスト）
  - [ ] ログイン → ホーム画面 → Tier 1 Training ダッシュボード
  - [ ] レッスン視聴 → クイズ実施 → スコア提出
  - [ ] 全4モジュール完了 → 修了証発行
- [ ] エラーハンドリングテスト
  - [ ] ネットワーク断の復旧
  - [ ] Firestore 権限エラーの処理
  - [ ] クイズ採点エラーのリトライ

---

## 2. Sep 16 朝の起動手順（08:00-09:00 JST）

### 08:00 - インフラ確認
```bash
# Firestore 状態確認
gcloud firestore operations list --project=safy-dev-japan

# Cloud Functions デプロイ状態確認
firebase functions:list --project=safy-dev-japan

# Cloud Logging アラート設定確認
gcloud alpha monitoring policies list --project=safy-dev-japan
```

### 08:30 - モジュール自動シード実行
```bash
# Sep 16 00:00 JST に自動実行される seedTier1ModulesOnSchedule を確認
# 以下のログで正常実行を確認
firebase functions:log --only seedTier1ModulesOnSchedule --project=safy-dev-japan
```

### 08:45 - 管理チーム通知
- Slack #tier1-training に開始通知
- 各社の HR 責任者に学習開始メール送信
- 運用ダッシュボード URL を共有

### 09:00 - 学習期間公式開始
- アプリ側で TrainingDashboardScreen 表示開始
- リアルタイムモニタリング開始

---

## 3. 学習期間中（Sep 16-22）の監視

### 日次チェック項目（毎朝 09:00 JST）

#### メトリクス確認
```sql
-- Tier 1 Training 進捗状況（各日）
SELECT 
  DATE(timestamp) as date,
  COUNT(DISTINCT employeeId) as total_attempts,
  COUNTIF(passed) as passed_count,
  ROUND(COUNTIF(passed) / COUNT(*) * 100, 1) as pass_rate
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE timestamp >= TIMESTAMP('2026-09-16')
  AND timestamp < TIMESTAMP('2026-09-23')
GROUP BY date
ORDER BY date DESC;

-- モジュール別完了率
SELECT 
  moduleId,
  COUNT(DISTINCT employeeId) as unique_students,
  COUNTIF(passed) as passed_students,
  ROUND(COUNTIF(passed) / COUNT(DISTINCT employeeId) * 100, 1) as completion_rate
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE timestamp >= TIMESTAMP('2026-09-16')
GROUP BY moduleId
ORDER BY completion_rate DESC;

-- Cloud Functions エラーレート
SELECT 
  resource.labels.function_name,
  COUNT(*) as total_calls,
  COUNTIF(severity = 'ERROR') as error_count,
  ROUND(COUNTIF(severity = 'ERROR') / COUNT(*) * 100, 2) as error_rate
FROM `safy-dev-japan.firebase_logs.cloudFunctions`
WHERE timestamp >= TIMESTAMP(CURRENT_DATE())
  AND timestamp < TIMESTAMP(CURRENT_DATE() + INTERVAL 1 DAY)
GROUP BY resource.labels.function_name
ORDER BY error_count DESC;
```

#### ダッシュボード監視
- **trainingAttempts**: 本日の提出数・合格率
- **certificateIssued**: 発行された修了証数
- **functionErrors**: recordTrainingProgress のエラー数
- **userActivity**: 日次 DAU（Daily Active Users）

#### アラート監視
- [ ] エラーレート > 1% → PagerDuty 通知
- [ ] 合格率 < 50%（日次） → Slack 警告
- [ ] Cloud Functions タイムアウト > 5回/日 → 調査

### 定期通知（Slack #tier1-training）

| 時刻 | 内容 |
|------|------|
| 09:15 | 前日の統計（参加者数、合格率、完了率） |
| 12:00 | 本日正午時点の中間報告 |
| 18:00 | 本日の終了報告（完了予定） |
| 23:00 | エラーログ・問題報告の集約 |

---

## 4. Sep 22（最終日）の対応

### Sep 22 09:00 - 最終日開始
- Slack に最終日通知
- 未完了者リスト確認
- 技術サポートスタンバイ体制確認

### Sep 22 18:00 - 最終スパート通知
```sql
-- 未完了モジュール一覧（4時間前）
SELECT 
  companyId,
  employeeId,
  ARRAY_AGG(DISTINCT moduleId IGNORE NULLS) as incomplete_modules,
  COUNT(DISTINCT moduleId) as modules_remaining
FROM (
  SELECT DISTINCT
    'company-id' as companyId,
    'employee-id' as employeeId,
    moduleId
  FROM (
    SELECT 'tier1-platform-tech' as moduleId
    UNION ALL
    SELECT 'tier1-operations'
    UNION ALL
    SELECT 'tier1-content-production'
    UNION ALL
    SELECT 'tier1-gtm-strategy'
  )
  WHERE moduleId NOT IN (
    SELECT DISTINCT moduleId
    FROM `trainingAttempts`
    WHERE employeeId = 'employee-id'
      AND passed = true
  )
)
GROUP BY companyId, employeeId;
```

### Sep 22 23:45 - ファイナルチェック
```bash
# 期限 1 分前の最終確認
firebase firestore:get --project=safy-dev-japan --collection=trainingAttempts
```

### Sep 22 23:59 - 期限切れ
- checkTrainingDeadline 関数トリガー
- 未完了者の trainingDeadlineStatus 記録
- 管理者への通知

### Sep 23 00:00+ - 事後処理
- [ ] 全42名の修了率確認
- [ ] 修了証発行数確認
- [ ] 期限超過者リスト確認
- [ ] 異常値・エラーの根本原因分析

---

## 5. トラブルシューティングガイド

### 症状: 「Firestore quota exceeded」

**原因**  
同時接続数が多すぎてクエリが制限された

**対応**
1. Cloud Monitoring で Firestore 読み書き/秒を確認
2. キャッシング機構を有効化（学習期間中は不可、次回向け）
3. 一部ユーザーに「ちょっと待ってから再試行」を促す

**予防**
- Sep 23 から段階的にユーザーを投入（Phase 2 soft launch）

---

### 症状: 「修了証が発行されない」

**原因チェック**
1. すべての 4 モジュール for ループが完了しているか
   ```sql
   SELECT moduleId, COUNT(*) 
   FROM trainingAttempts 
   WHERE employeeId = 'XXX' 
   GROUP BY moduleId;
   ```

2. Cloud Functions ログを確認
   ```bash
   firebase functions:log --only issueTrainingCertificate
   ```

3. Firestore trainingCertificates コレクションを確認

**対応**
- 問題が見つかった場合は、Manual Issuance スクリプトで手動発行

---

### 症状: 「クイズスコアが 0 点」

**原因チェック**
1. 選択肢の送信形式確認（correctIndex は 0-indexed）
2. Firestore quizQuestions の correctIndex 確認
3. recordTrainingProgress のスコア計算ロジック確認

**対応**
```typescript
// Manual Score Recalculation
const attempt = await db.doc(`companies/{companyId}/trainingAttempts/{attemptId}`).get();
const questions = await db.collection(`modules/{moduleId}/quizQuestions`).get();

// 再計算実行
const newScore = calculateScore(attempt.data().selectedAnswers, questions.docs);
await db.doc(...).update({ score: newScore, passed: newScore >= 80 });
```

---

### 症状: 「プッシュ通知が届かない」

**原因チェック**
1. FCM トークンが登録されているか
   ```sql
   SELECT fcmToken FROM `companies/{companyId}/employees`
   WHERE fcmToken IS NOT NULL
   ```

2. デバイスが通知許可を与えているか

3. Firebase Cloud Messaging のステータス確認

**対応**
- Slack で直接通知（フォールバック）
- 手動メール送信

---

## 6. GATE 3 検証基準（Sep 23）

| 項目 | 目標 | 判定 |
|------|------|------|
| 全体修了率 | ≥ 75% | ✅/❌ |
| モジュール別完了率 | 各 ≥ 70% | ✅/❌ |
| エラーレート | < 1% | ✅/❌ |
| API 可用性 | ≥ 99.5% | ✅/❌ |
| 修了証発行数 | 期待値の ±5% | ✅/❌ |

**GATE 3 合格条件**: すべてのチェック項目が ✅

---

## 7. Sep 30 本番リリース前の準備

### Sep 23-29: 事後分析
- [ ] ユーザーフィードバック収集
- [ ] UI/UX 改善点の抽出
- [ ] パフォーマンス最適化
- [ ] セキュリティ監査

### Sep 29: 最終チェック
- [ ] Production 環境チェックリスト確認
- [ ] 99.9% SLA 達成準備
- [ ] 24/7 On-Call ローテーション確認
- [ ] インシデント対応マニュアル確認

### Sep 30: 本番リリース
- Full Launch へ移行
- 全企業利用可能にする

---

**作成者**: Safy DevOps Team  
**最終更新**: Sep 16, 2026  
**次回レビュー**: Sep 23, 2026 (事後分析)
