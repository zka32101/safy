# Sep 30 本番リリース前チェックリスト

**対象**: Tier 1 Training 本番リリース（Oct 1 本格運用開始前）  
**期限**: Sep 29 18:00 JST  
**実施者**: DevOps + QA + Engineering チーム

---

## 1. インフラストラクチャ・セキュリティ

### Firestore
- [ ] 本番環境の Firestore キャパシティ確認（100+ 同時接続対応）
- [ ] Firestore セキュリティルール適用確認
  - [ ] `trainingAttempts`: 本人 & 管理者のみ読み書き
  - [ ] `trainingCertificates`: 本人 & 管理者のみ読み取り
  - [ ] `trainingDeadlineStatus`: 管理者のみ読み取り
  - [ ] インデックス作成完了確認
- [ ] バックアップ戦略確認（日次スケジュール）
- [ ] Firestore Emulator 削除（本番環境では不要）

### Cloud Functions
- [ ] すべての関数がデプロイ確認
  - [ ] `recordTrainingProgress`
  - [ ] `issueTrainingCertificate`
  - [ ] `checkTrainingDeadline`
  - [ ] `getGate3Metrics`
- [ ] メモリ割当確認（512MB 推奨以上）
- [ ] タイムアウト設定確認（60 秒以上）
- [ ] 環境変数設定確認（なければスキップ）
- [ ] IAM 権限確認（Firestore, Logging アクセス）

### Firebase Authentication
- [ ] 本番環境で有効化確認
- [ ] Email/Password 認証有効化確認
- [ ] SAML/OIDC SSO 設定確認（該当する場合）
- [ ] 2FA 要件確認（必須/推奨/無効）
- [ ] ユーザーサッカー対策（レート制限）有効化

### Cloud Logging & Monitoring
- [ ] Cloud Logging アラート設定確認
  - [ ] Error rate > 1% → Page/Slack
  - [ ] Functions timeout > 5回/日 → Slack
  - [ ] Firestore quota exceeded → Page
- [ ] Cloud Monitoring ダッシュボード作成
  - [ ] Daily active users (DAU)
  - [ ] Training completion rate (%)
  - [ ] Error rate (%)
  - [ ] API latency (ms)
  - [ ] Firestore reads/writes per sec
- [ ] ログ保持期間設定（推奨: 30 日以上）

### VPC & Network
- [ ] VPC ファイアウォールルール確認
- [ ] Cloud NAT 設定確認（Firestore アクセス）
- [ ] DDoS 保護有効化確認（Cloud Armor）
- [ ] WAF ルール設定確認（不正アクセス防止）

---

## 2. アプリケーション検証

### Flutter アプリ（本番ビルド）
- [ ] Release ビルド作成確認
  ```bash
  flutter build apk --release --split-per-abi
  flutter build ipa --release
  ```
- [ ] APK/IPA ファイルサイズ確認（<100MB が目安）
- [ ] アプリ署名確認
  - [ ] Android: Keystore 署名
  - [ ] iOS: 本番証明書署名
- [ ] Obfuscation 有効化確認（コード難読化）
- [ ] Firebase Crashlytics 設定確認
  - [ ] 本番環境プロジェクト指定
  - [ ] Slack 通知設定

### UI/UX テスト（実機）
- [ ] Training Dashboard
  - [ ] 4 モジュール表示確認
  - [ ] 期限カウントダウン表示（Sep 22 23:59 のみ）
  - [ ] 進捗バー表示確認（0-100%）
- [ ] Lesson/Quiz Flow
  - [ ] レッスン動画再生確認
  - [ ] クイズ 5 問表示確認
  - [ ] 採点ロジック確認（80% 以上で合格）
- [ ] Certificate Screen
  - [ ] 修了証表示確認
  - [ ] 修了証番号正確性確認
  - [ ] PDF/画像エクスポート確認
- [ ] Error Handling
  - [ ] ネットワーク切断時のエラーメッセージ
  - [ ] Firestore 権限エラー時の対応
  - [ ] タイムアウト時の自動リトライ

### パフォーマンス測定
- [ ] アプリ起動時間 < 3 秒
- [ ] Dashboard 画面遷移 < 2 秒
- [ ] クイズ採点 < 5 秒
- [ ] 修了証発行 < 10 秒
- [ ] メモリ使用量 < 200MB
- [ ] バッテリー消費（1 時間連続使用で < 15% 低下）

---

## 3. データベース・ログ

### BigQuery 準備
- [ ] Firebase Logs → BigQuery エクスポート設定
  - [ ] `firebase_logs.trainingAttempts`
  - [ ] `firebase_logs.trainingCertificates`
  - [ ] `firebase_logs.trainingDeadlineStatus`
  - [ ] `firebase_logs.cloudFunctions`
- [ ] TIER1_MONITORING_QUERIES.sql 登録確認
- [ ] Daily monitoring job スケジュール設定
  - [ ] 09:15: リアルタイム統計
  - [ ] 12:00: 中間報告
  - [ ] 18:00: 終了報告
  - [ ] 23:00: エラーログ集約

### 本番データ確認
- [ ] Test ユーザー削除（本番環境から）
- [ ] Tier 1 Training モジュール本番登録確認
  - [ ] 4 モジュール × 4 レッスン × 5 クイズ
  - [ ] 全問題の日本語テキスト確認
  - [ ] 画像/動画ファイル参照確認
- [ ] 42 名従業員マスターデータ登録確認
  - [ ] 企業別グルーピング
  - [ ] FCM トークン登録状況確認（<80% なら通知）

---

## 4. セキュリティ監査

### Code Review
- [ ] 本番環境機密情報（API キー等）が含まれていないか確認
- [ ] SQL インジェクション対策確認
- [ ] XSS 対策確認（Dart 側の HTML エスケープ）
- [ ] CSRF トークン確認（API エンドポイント）
- [ ] レート制限実装確認

### Dependency Audit
- [ ] `flutter pub outdated` で脆弱性確認
- [ ] `npm audit` で npm パッケージ脆弱性確認
  ```bash
  cd functions && npm audit --production
  ```
- [ ] 既知の脆弱性がある場合、パッチ適用 or 代替案検討

### Penetration Testing (Optional)
- [ ] API エンドポイント脆弱性テスト
- [ ] Firestore セキュリティルール穴探し
- [ ] 認証・認可ロジックテスト
- [ ] 暗号化通信確認（全通信 HTTPS）

---

## 5. 運用準備

### ドキュメント
- [ ] TIER1_TRAINING_OPERATIONS.md 最終確認
- [ ] TIER1_MONITORING_QUERIES.sql 動作確認
- [ ] トラブルシューティングガイド確認
- [ ] インシデント対応マニュアル作成
  - [ ] エスカレーション連絡先
  - [ ] On-Call ローテーション
  - [ ] RTO/RPO 目標値設定

### ユーザー・コミュニケーション
- [ ] 42 名従業員への事前通知メール送信
  - [ ] 学習期間: Sep 16-22（Oct 1 以降のための学習）
  - [ ] 4 モジュール × 4 時間 = 計 16 時間の自習
  - [ ] 80% 合格基準
  - [ ] 修了証自動発行（全 4 モジュール完了時）
- [ ] 企業ごとの HR 責任者にオンボーディング資料配布
- [ ] サポート窓口（Slack #tier1-training）の周知

### 管理画面・ダッシュボード
- [ ] GATE 3 検証ダッシュボード (Sep 23) 準備
  - [ ] BigQuery メトリクス集計確認
  - [ ] Go/No-Go 判定ロジック確認
  - [ ] 管理者のみアクセス可能か確認
- [ ] 運用ダッシュボード (Google Data Studio) 作成
  - [ ] 日別完了率グラフ
  - [ ] モジュール別完了率
  - [ ] エラーレート推移
  - [ ] リアルタイムユーザー数

---

## 6. 本番環境最終チェック（Sep 29）

### データ・設定
- [ ] Firestore 本番環境に Tier 1 Training モジュール完全登録
- [ ] 42 名従業員マスター情報正確性確認（ダブルチェック）
- [ ] Sep 16 09:00 JST 学習期間開始タイマー設定
- [ ] Sep 22 23:59 JST 期限設定確認

### CI/CD Pipeline
- [ ] GitHub Actions: Flutter テスト → APK ビルド → Firebase Hosting デプロイ
- [ ] Cloud Functions デプロイ自動化確認
- [ ] Firestore セキュリティルール自動デプロイ確認
- [ ] Firebase Emulator から本番環境への切り替え確認

### ロールアウト計画
- [ ] Phase 1: Sep 16-22 学習期間（全 42 名）
- [ ] Phase 2: Sep 23 GATE 3 検証 & 分析
- [ ] Phase 3: Sep 30 Oct 1 本格運用前の最終調整
- [ ] Phase 4: Oct 1 本番リリース（全機能有効化）

### エスカレーション体制
- [ ] 24/7 On-Call エンジニア確保
- [ ] Slack #tier1-training-ops チャネル作成
- [ ] PagerDuty インテグレーション確認
  - [ ] エラーレート > 1% → P1 アラート
  - [ ] Functions タイムアウト > 5回 → P2 アラート
  - [ ] Firestore quota 達成 → P0 アラート

---

## 7. 本番リリース当日（Oct 1）

### 朝（08:00-09:00 JST）
- [ ] インフラ状態確認
  ```bash
  gcloud firestore operations list --project=safy-prod-japan
  firebase functions:list --project=safy-prod-japan
  ```
- [ ] Cloud Monitoring ダッシュボード確認（異常値なし）
- [ ] BigQuery クエリ実行（Sept 16-22 実績確認）

### 09:00 本番リリース開始
- [ ] Slack #tier1-training-ops に開始通知
- [ ] モニタリング強化（リアルタイム監視開始）
- [ ] 42 名従業員へのウェルカムメール送信
- [ ] 管理者向け運用ガイド最終通知

### 監視（Sep 16-22 期間中）
- [ ] 日次メトリクス監視（毎日 09:15, 12:00, 18:00, 23:00 JST）
- [ ] エラーログ集約・分析（毎日 23:00 JST）
- [ ] 技術サポートスタンバイ（09:00-23:00 JST）

### Sep 23 GATE 3 検証
- [ ] 09:00 GATE 3 ダッシュボード実行
- [ ] 5 つの指標すべて確認
- [ ] Go/No-Go 判定
- [ ] 経営層への報告

---

## チェックリスト確認

```
【インフラ・セキュリティ】
[ ] Firestore キャパシティ & セキュリティルール
[ ] Cloud Functions デプロイ & IAM
[ ] Firebase Authentication
[ ] Logging & Monitoring アラート設定
[ ] VPC & Network セキュリティ

【アプリケーション検証】
[ ] Release ビルド & 署名
[ ] 実機テスト（UI/UX/パフォーマンス）
[ ] Crashlytics 設定

【データベース・ログ】
[ ] BigQuery エクスポート設定
[ ] 本番モジュール & ユーザーデータ登録
[ ] Test データ削除

【セキュリティ監査】
[ ] Code Review（機密情報・脆弱性）
[ ] Dependency Audit
[ ] 穿刺テスト（Optional）

【運用準備】
[ ] ドキュメント確認
[ ] ユーザー・企業への通知
[ ] 管理画面・ダッシュボード準備
[ ] On-Call 体制確保

【本番環境最終】
[ ] Firestore 本番登録確認
[ ] CI/CD パイプライン確認
[ ] ロールアウト計画確認
[ ] エスカレーション体制確認

【本番リリース】
[ ] 朝のインフラ確認
[ ] 09:00 本番リリース開始
[ ] 監視開始（Sep 16-22）
[ ] Sep 23 GATE 3 検証実施
```

**最終判定**: ☐ GO / ☐ NO-GO

---

**作成者**: DevOps Team  
**最終更新**: Sep 23, 2026  
**次回レビュー**: Oct 1, 2026 (本番リリース)
