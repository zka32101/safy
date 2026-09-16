# Cloud Logging & Monitoring設定ガイド

## 概要

Safy Cloud Functions の監視・アラート設定。本番環境での可視化とトラブルシューティング。

---

## 1. Cloud Logging設定

### 1.1 アラート設定 (Cloud Console → Monitoring → Alert Policies)

#### Alert 1: Cloud Functions エラーレート > 1%
```yaml
Metric Type: logging.googleapis.com/user/function_errors
Resource Type: cloud_function
Condition:
  - threshold > 1
  - duration: 5 minutes
  - aggregation: RATE
Notification Channels: [Slack, PagerDuty]
```

**対応**: 自動スケール削減、サーキットブレーカー導入、リソース追加

---

#### Alert 2: submitQuizAttempt スコア計算エラー
```
Log Filter:
  resource.type = "cloud_function"
  resource.labels.function_name = "submitQuizAttempt"
  severity >= "ERROR"
  
Condition: count > 5 in 10 minutes
Action: Slack通知 + error logを保存
```

**対応**: Firebase 接続確認、Firestore quota確認

---

#### Alert 3: generateOriginalContent API レート制限
```
Log Filter:
  resource.type = "cloud_function"
  resource.labels.function_name = "generateOriginalContent"
  jsonPayload.message =~ "429|rate limit"
  
Condition: count > 3 in 1 hour
Action: PagerDuty エスカレーション
```

**対応**: Anthropic API quota増加、キュー機構導入

---

#### Alert 4: sendMonthlyReports 失敗通知
```
Log Filter:
  resource.type = "cloud_function"
  resource.labels.function_name = "sendMonthlyReports"
  jsonPayload.message =~ "失敗通知メール送信"
  
Condition: count > 0
Action: Slack通知 (重要度: HIGH)
```

---

### 1.2 Logging Sinks (ログをリアルタイム集約)

#### Sink 1: ERROR/CRITICAL → BigQuery
```bash
gcloud logging sinks create errors-to-bq \
  bigquery.googleapis.com/projects/safy-dev-japan/datasets/firebase_logs \
  --log-filter='severity >= "ERROR" resource.type = "cloud_function"'
```

**用途**: 本番エラー分析、トレンド検出、根本原因分析

---

#### Sink 2: INFO/WARNING → Cloud Storage (アーカイブ)
```bash
gcloud logging sinks create logs-archive \
  storage.googleapis.com/safy-dev-japan-log-archive \
  --log-filter='resource.type = "cloud_function"'
```

**保持期間**: 90日

---

## 2. 監視ダッシュボード (Cloud Console用クエリ集)

### Query 1: Functions実行サマリー (直近24h)
```sql
-- Cloud Logging Query Language (StackDriver)
resource.type = "cloud_function"
| group_by(resource.labels.function_name,
    [
      value_function_calls: count(all_logs),
      value_error_rate: count(severity >= "ERROR") / count(all_logs),
      value_avg_latency: mean(labels.execution_time_ms)
    ]
  )
```

**ダッシュボード**: 関数ごとの呼び出し数・エラー率・平均レイテンシー

---

### Query 2: submitQuizAttempt パフォーマンス
```sql
resource.type = "cloud_function"
resource.labels.function_name = "submitQuizAttempt"
| group_by(1h,
    [
      value_calls: count(all_logs),
      value_p50_latency: percentile(labels.execution_time_ms, 50),
      value_p99_latency: percentile(labels.execution_time_ms, 99),
      value_errors: count(severity >= "ERROR")
    ]
  )
```

**グラフ**: 時系列でレイテンシー・エラー率を監視

---

### Query 3: 月次レポート送信状況
```sql
resource.type = "cloud_function"
resource.labels.function_name = "sendMonthlyReports"
| filter(timestamp > "2026-09-01T00:00:00Z")
| group_by(resource.labels.execution_id,
    [
      value_company_id: labels.company_id,
      value_recipient: labels.contact_email,
      value_status: if(severity >= "ERROR", "FAILED", "SUCCESS"),
      value_timestamp: max(timestamp)
    ]
  )
```

**用途**: 全社向けレポート送信履歴、再送が必要な会社の特定

---

### Query 4: AIコンテンツ生成 レート制限分析
```sql
resource.type = "cloud_function"
resource.labels.function_name = "generateOriginalContent"
| filter(jsonPayload.message =~ "429|rate limit|retry")
| group_by(
    [
      value_count: count(all_logs),
      value_retry_count: count(jsonPayload.message =~ "リトライ"),
      value_rate_limit_hits: count(jsonPayload.message =~ "429")
    ]
  )
```

**アクション**: レート制限が多い場合は Anthropic quota増加リクエスト

---

## 3. デプロイ前チェックリスト

```
[ ] Alert policies 5つすべて設定完了
[ ] BigQuery sink 作成・テスト済み
[ ] Cloud Storage archive sink 作成・テスト済み
[ ] ダッシュボードクエリ動作確認
[ ] Slack/PagerDuty 通知チャネル設定
[ ] アラート閾値の実環境調整 (テスト期間2週間)
[ ] Error handling retry logic 検証
[ ] Failed email notification テスト完了
```

---

## 4. トラブルシューティングガイド

### 症状: submitQuizAttempt でスコア計算エラー

**原因チェック**:
1. Firestore接続確認
   ```bash
   gcloud firestore operations list --project=safy-dev-japan
   ```

2. エラーログ確認
   ```
   Log Filter:
     resource.type = "cloud_function"
     resource.labels.function_name = "submitQuizAttempt"
     severity = "ERROR"
   ```

3. Quota確認
   ```bash
   gcloud compute project-info describe --project=safy-dev-japan \
     --format="value(quotas[].usage)"
   ```

---

### 症状: generateOriginalContent が429エラーで頻繁にリトライ

**原因**: Anthropic API レート制限に達した

**対応**:
1. 短期: リトライ待機時間調整 (backoff factor増加)
2. 中期: キュー機構を導入 (Cloud Tasks)
3. 長期: Anthropic quota増加リクエスト

---

### 症状: sendMonthlyReports が失敗メール通知を送信

**確認事項**:
1. SendGrid API key 有効期限確認
2. FromEmail アドレスが SendGrid で認証済みか確認
3. 受信側メールサーバーが送信を拒否していないか確認 (SPF/DKIM)

---

## 5. メトリクス保持期間

- **ログ**: 30日間 (Cloud Logging無料枠)
- **BigQuery**: 無制限 (課金対象)
- **Cloud Storage**: 90日間 (ポリシー設定)

---

**最終更新**: Sep 16, 2026  
**作成者**: Safy DevOps Team  
**次回レビュー**: Sep 30, 2026
