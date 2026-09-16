-- Tier 1 Training Sep 16-22 監視・分析用 SQL クエリ集
-- 実行環境: BigQuery (safy-dev-japan プロジェクト)
-- テーブル: firebase_logs.trainingAttempts, trainingCertificates, cloudFunctions

-- ============================================================
-- 1. リアルタイムダッシュボード用クエリ（毎日朝 09:00 実行）
-- ============================================================

-- Query 1.1: 本日の進捗サマリー
SELECT
  COUNT(DISTINCT employeeId) as unique_students,
  COUNT(*) as total_attempts,
  COUNTIF(passed) as passed_attempts,
  ROUND(COUNTIF(passed) / COUNT(*) * 100, 1) as pass_rate,
  MIN(score) as min_score,
  ROUND(AVG(score), 1) as avg_score,
  MAX(score) as max_score
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE DATE(timestamp, 'Asia/Tokyo') = CURRENT_DATE('Asia/Tokyo')
  AND timestamp >= TIMESTAMP('2026-09-16 00:00:00', 'Asia/Tokyo');

-- Query 1.2: モジュール別の完了状況
SELECT
  moduleId,
  COUNT(DISTINCT employeeId) as unique_students,
  COUNTIF(passed) as passed_count,
  ROUND(COUNTIF(passed) / COUNT(DISTINCT employeeId) * 100, 1) as completion_rate,
  ROUND(AVG(score), 1) as avg_score
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE DATE(timestamp, 'Asia/Tokyo') >= '2026-09-16'
  AND DATE(timestamp, 'Asia/Tokyo') <= CURRENT_DATE('Asia/Tokyo')
GROUP BY moduleId
ORDER BY completion_rate DESC;

-- Query 1.3: 企業別の進捗率
SELECT
  companyId,
  COUNT(DISTINCT employeeId) as enrolled_employees,
  ROUND(
    COUNT(DISTINCT CASE
      WHEN moduleId IN (
        'tier1-platform-tech',
        'tier1-operations',
        'tier1-content-production',
        'tier1-gtm-strategy'
      ) AND passed THEN employeeId END
    ) / 4 / COUNT(DISTINCT employeeId) * 100, 1
  ) as avg_completion_rate
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE DATE(timestamp, 'Asia/Tokyo') >= '2026-09-16'
GROUP BY companyId
ORDER BY avg_completion_rate DESC;

-- Query 1.4: 発行された修了証数
SELECT
  DATE(issuedAt, 'Asia/Tokyo') as issue_date,
  COUNT(*) as certificates_issued,
  COUNT(DISTINCT employeeId) as employees_completed
FROM `safy-dev-japan.firebase_logs.trainingCertificates`
WHERE issuedAt >= TIMESTAMP('2026-09-16', 'Asia/Tokyo')
  AND issuedAt < TIMESTAMP('2026-09-23', 'Asia/Tokyo')
GROUP BY issue_date
ORDER BY issue_date DESC;

-- ============================================================
-- 2. トレンド分析（学習期間全体）
-- ============================================================

-- Query 2.1: 日別の合格率推移
SELECT
  DATE(timestamp, 'Asia/Tokyo') as date,
  COUNT(*) as total_attempts,
  COUNTIF(passed) as passed_count,
  ROUND(COUNTIF(passed) / COUNT(*) * 100, 1) as daily_pass_rate,
  ROUND(AVG(score), 1) as avg_score
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE timestamp >= TIMESTAMP('2026-09-16', 'Asia/Tokyo')
  AND timestamp < TIMESTAMP('2026-09-23', 'Asia/Tokyo')
GROUP BY date
ORDER BY date;

-- Query 2.2: スコア分布（ヒストグラム）
SELECT
  CASE
    WHEN score >= 90 THEN '90-100'
    WHEN score >= 80 THEN '80-89'
    WHEN score >= 70 THEN '70-79'
    WHEN score >= 60 THEN '60-69'
    ELSE '<60'
  END as score_range,
  COUNT(*) as count,
  ROUND(COUNT(*) / (SELECT COUNT(*) FROM `safy-dev-japan.firebase_logs.trainingAttempts`) * 100, 1) as percentage
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE timestamp >= TIMESTAMP('2026-09-16', 'Asia/Tokyo')
GROUP BY score_range
ORDER BY score_range DESC;

-- Query 2.3: リトライ分析（同じモジュール複数回提出）
SELECT
  employeeId,
  moduleId,
  COUNT(*) as attempt_count,
  MIN(score) as first_attempt_score,
  MAX(score) as best_score,
  ARRAY_AGG(score ORDER BY timestamp) as score_history
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE timestamp >= TIMESTAMP('2026-09-16', 'Asia/Tokyo')
GROUP BY employeeId, moduleId
HAVING COUNT(*) > 1
ORDER BY attempt_count DESC;

-- ============================================================
-- 3. 問題検出・アラート用クエリ
-- ============================================================

-- Query 3.1: エラーレート監視（Cloud Functions）
SELECT
  DATE(timestamp) as date,
  HOUR(timestamp) as hour,
  COUNT(*) as total_calls,
  COUNTIF(severity >= 'ERROR') as error_count,
  ROUND(COUNTIF(severity >= 'ERROR') / COUNT(*) * 100, 2) as error_rate
FROM `safy-dev-japan.firebase_logs.cloudFunctions`
WHERE timestamp >= TIMESTAMP('2026-09-16')
  AND jsonPayload.function IN (
    'recordTrainingProgress',
    'issueTrainingCertificate',
    'checkTrainingDeadline'
  )
GROUP BY date, hour
HAVING error_rate > 1.0
ORDER BY error_rate DESC;

-- Query 3.2: 低い合格率のモジュール特定
SELECT
  moduleId,
  COUNT(*) as total_attempts,
  COUNTIF(passed) as passed_count,
  ROUND(COUNTIF(passed) / COUNT(*) * 100, 1) as pass_rate,
  ROUND(AVG(score), 1) as avg_score
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE timestamp >= TIMESTAMP('2026-09-16', 'Asia/Tokyo')
GROUP BY moduleId
HAVING ROUND(COUNTIF(passed) / COUNT(*) * 100, 1) < 70
ORDER BY pass_rate ASC;

-- Query 3.3: 期限超過者の特定
SELECT
  employeeId,
  ARRAY_AGG(DISTINCT moduleId) as incomplete_modules,
  COUNT(DISTINCT moduleId) as incomplete_count
FROM (
  SELECT DISTINCT 'tier1-platform-tech' as moduleId, 'emp-001' as employeeId
  UNION ALL
  SELECT 'tier1-operations', 'emp-001'
  UNION ALL
  SELECT 'tier1-content-production', 'emp-001'
  UNION ALL
  SELECT 'tier1-gtm-strategy', 'emp-001'
)
WHERE moduleId NOT IN (
  SELECT DISTINCT moduleId
  FROM `safy-dev-japan.firebase_logs.trainingAttempts`
  WHERE employeeId = CAST(employeeId AS STRING)
    AND passed = true
)
GROUP BY employeeId
HAVING COUNT(DISTINCT moduleId) > 0;

-- Query 3.4: 異常なレイテンシの検出
SELECT
  jsonPayload.function as function_name,
  ROUND(AVG(CAST(jsonPayload.duration_ms AS FLOAT64)), 1) as avg_latency_ms,
  ROUND(MAX(CAST(jsonPayload.duration_ms AS FLOAT64)), 1) as max_latency_ms,
  COUNT(*) as invocation_count
FROM `safy-dev-japan.firebase_logs.cloudFunctions`
WHERE timestamp >= TIMESTAMP('2026-09-16')
  AND jsonPayload.duration_ms IS NOT NULL
GROUP BY jsonPayload.function
HAVING AVG(CAST(jsonPayload.duration_ms AS FLOAT64)) > 500;

-- ============================================================
-- 4. GATE 3 検証用クエリ（Sep 23 実行）
-- ============================================================

-- Query 4.1: GATE 3 指標集計
SELECT
  'All Modules Completion Rate' as metric,
  ROUND(
    COUNT(DISTINCT CASE
      WHEN (
        SELECT COUNT(DISTINCT moduleId)
        FROM `safy-dev-japan.firebase_logs.trainingAttempts` t2
        WHERE t2.employeeId = t1.employeeId
          AND t2.passed = true
          AND t2.moduleId IN (
            'tier1-platform-tech',
            'tier1-operations',
            'tier1-content-production',
            'tier1-gtm-strategy'
          )
      ) = 4 THEN employeeId END
    ) / COUNT(DISTINCT employeeId) * 100, 1
  ) as completion_rate_percent
FROM `safy-dev-japan.firebase_logs.trainingAttempts` t1
WHERE timestamp >= TIMESTAMP('2026-09-16', 'Asia/Tokyo')
  AND timestamp < TIMESTAMP('2026-09-23', 'Asia/Tokyo');

-- Query 4.2: モジュール別の最終合格率
SELECT
  moduleId,
  COUNT(DISTINCT employeeId) as total_students,
  COUNTIF(passed) as passed_students,
  ROUND(COUNTIF(passed) / COUNT(DISTINCT employeeId) * 100, 1) as final_pass_rate
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE timestamp >= TIMESTAMP('2026-09-16', 'Asia/Tokyo')
  AND timestamp < TIMESTAMP('2026-09-23', 'Asia/Tokyo')
GROUP BY moduleId
ORDER BY moduleId;

-- Query 4.3: 期限内提出率
SELECT
  ROUND(
    COUNT(CASE
      WHEN timestamp < TIMESTAMP('2026-09-22 23:59:59', 'Asia/Tokyo') THEN 1
    END) / COUNT(*) * 100, 1
  ) as on_time_submission_rate
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE timestamp >= TIMESTAMP('2026-09-16', 'Asia/Tokyo')
  AND timestamp < TIMESTAMP('2026-09-23', 'Asia/Tokyo');

-- Query 4.4: Cloud Functions エラーレート（全期間）
SELECT
  ROUND(
    COUNTIF(severity >= 'ERROR') / COUNT(*) * 100, 2
  ) as overall_error_rate
FROM `safy-dev-japan.firebase_logs.cloudFunctions`
WHERE timestamp >= TIMESTAMP('2026-09-16')
  AND timestamp < TIMESTAMP('2026-09-23');

-- Query 4.5: 修了証発行総数
SELECT
  COUNT(*) as total_certificates_issued,
  COUNT(DISTINCT employeeId) as unique_employees_completed
FROM `safy-dev-japan.firebase_logs.trainingCertificates`
WHERE issuedAt >= TIMESTAMP('2026-09-16', 'Asia/Tokyo')
  AND issuedAt < TIMESTAMP('2026-09-23', 'Asia/Tokyo');

-- ============================================================
-- 5. デバッグ用クエリ
-- ============================================================

-- Query 5.1: 特定ユーザーの詳細記録
SELECT
  employeeId,
  moduleId,
  score,
  passed,
  attemptedAt,
  timestamp
FROM `safy-dev-japan.firebase_logs.trainingAttempts`
WHERE employeeId = 'TARGET_USER_ID'
ORDER BY timestamp;

-- Query 5.2: 特定モジュールのクイズ問題確認
SELECT
  id,
  question,
  correctIndex,
  ARRAY_LENGTH(choices) as choice_count
FROM `safy-dev-japan.firebase_logs.modules`
WHERE moduleId = 'tier1-platform-tech'
ORDER BY id;

-- Query 5.3: Cloud Functions ログの詳細
SELECT
  timestamp,
  jsonPayload.function,
  jsonPayload.message,
  severity,
  jsonPayload.error
FROM `safy-dev-japan.firebase_logs.cloudFunctions`
WHERE jsonPayload.function = 'recordTrainingProgress'
  AND timestamp >= TIMESTAMP('2026-09-16')
ORDER BY timestamp DESC
LIMIT 100;

-- ============================================================
-- 6. レポート用クエリ（経営層向け）
-- ============================================================

-- Query 6.1: エグゼクティブサマリー
SELECT
  TIMESTAMP('2026-09-16') as training_start_date,
  CURRENT_TIMESTAMP() as report_date,
  DATE_DIFF(CURRENT_DATE('Asia/Tokyo'), '2026-09-16', DAY) as days_elapsed,
  COUNT(DISTINCT employeeId) as total_participants,
  ROUND(
    COUNT(DISTINCT CASE
      WHEN (
        SELECT COUNT(DISTINCT moduleId)
        FROM `safy-dev-japan.firebase_logs.trainingAttempts` t2
        WHERE t2.employeeId = t1.employeeId AND t2.passed = true
      ) = 4 THEN employeeId END
    ) / COUNT(DISTINCT employeeId) * 100, 1
  ) as completion_rate_percent,
  COUNT(*) as total_attempts,
  ROUND(AVG(score), 1) as average_score
FROM `safy-dev-japan.firebase_logs.trainingAttempts` t1
WHERE timestamp >= TIMESTAMP('2026-09-16', 'Asia/Tokyo');

---
-- 実行方法:
-- 1. BigQuery コンソールを開く
-- 2. プロジェクト: safy-dev-japan
-- 3. SQL クエリをコピーして実行
-- 4. 結果をダッシュボードに追加
--
-- 推奨実行スケジュール:
-- - Query 1.x: 毎日 09:15 JST
-- - Query 2.x: 毎日 18:00 JST
-- - Query 3.x: リアルタイム監視（アラート設定時）
-- - Query 4.x: Sep 23 00:00 JST（GATE 3 検証）
-- - Query 6.x: Sep 23 09:00 JST（事後分析）
