# Firebase セットアップガイド (Sep 9)
## Firebase Setup Guide for Sep 9 Execution

**バージョン**: 1.0  
**最終更新**: 2026-09-05  
**対象**: development 環境 (safy-dev-japan)  
**期限**: Sep 15, 23:59 JST (GATE 2 検証)

---

## 📋 クイックスタート（推奨）

Sep 9 に以下の **1つのコマンド** を実行するだけです：

```bash
cd /home/user/project-033
./bin/sep9-firebase-setup.sh safy-dev-japan
```

**所要時間**: 30-45 分

---

## 🎯 スクリプト一覧

| スクリプト | 用途 | 実行時間 |
|----------|------|--------|
| `sep9-firebase-setup.sh` | **マスタースクリプト** (全体) | 30-45分 |
| `firebase-setup-complete.sh` | 詳細なセットアップ (ステップバイステップ) | 60分+ |
| `deploy-functions.sh` | Functions ビルド・デプロイのみ | 10-15分 |
| `seed-firestore.sh` | Firestore 初期データ投入のみ | 5-10分 |

---

## 🚀 Sep 9 実行フロー（推奨）

### 08:00 - 10:00: Phase 7 API Design Review (会議中)
```bash
# 会議の合間に事前準備
./bin/sep9-firebase-setup.sh safy-dev-japan --build-only
```

### 10:00 - 12:00: Functions デプロイ
```bash
# Functions をデプロイ（ビルド済み）
./bin/sep9-firebase-setup.sh safy-dev-japan --functions-only
```

### 12:00 - 14:30: Firestore & Analytics セットアップ
```bash
# 残りの設定を自動実行
./bin/sep9-firebase-setup.sh safy-dev-japan --skip-seed
```

---

## 📖 詳細セットアップ（ステップバイステップ）

### 前提条件

```bash
# 1. Firebase CLI インストール
npm install -g firebase-tools

# 2. Firebase ログイン
firebase login

# 3. プロジェクトを確認
firebase projects:list
```

### Step 1: ビルド確認

```bash
cd /home/user/project-033
./bin/deploy-functions.sh safy-dev-japan --build-only
```

**期待される出力**:
```
✓ ビルド成功
```

### Step 2: Functions デプロイ

```bash
./bin/deploy-functions.sh safy-dev-japan
```

**実行時に聞かれる項目**:
- [ ] SendGrid API Key (オプション)
- [ ] SendGrid From Email (オプション)
- [ ] Anthropic API Key (オプション)

**デプロイ前に Secrets 設定（推奨）**:
```bash
firebase functions:secrets:set SENDGRID_API_KEY --project=safy-dev-japan
firebase functions:secrets:set SENDGRID_FROM_EMAIL --project=safy-dev-japan
firebase functions:secrets:set ANTHROPIC_API_KEY --project=safy-dev-japan
```

### Step 3: Firestore 初期データ投入

```bash
./bin/seed-firestore.sh safy-dev-japan
```

**投入データ**:
- `industries`: 10+ 業界マスタ
- `modules`: 18 研修モジュール
- `companies/{companyId}/employees`: テストユーザー 4 名
- `companies/{companyId}/enrollments`: テスト受講 3 件

---

## 🔧 オプションコマンド

### Functions ビルドのみ（デプロイなし）

```bash
./bin/deploy-functions.sh safy-dev-japan --build-only
```

**用途**: ビルドエラーの確認、CI/CD パイプライン検証

### Functions デプロイのみ（ビルド済み）

```bash
./bin/deploy-functions.sh safy-dev-japan --deploy-only
```

**用途**: デプロイ失敗から再実行

### Firestore シード投入（Dry Run）

```bash
./bin/seed-firestore.sh safy-dev-japan --dry-run
```

**用途**: 実際に投入する前に確認

### マスタースクリプトのスキップオプション

```bash
# Functions のみ
./bin/sep9-firebase-setup.sh safy-dev-japan --functions-only

# ビルドのみ
./bin/sep9-firebase-setup.sh safy-dev-japan --build-only

# Firestore シード投入をスキップ
./bin/sep9-firebase-setup.sh safy-dev-japan --skip-seed
```

---

## 📊 各ステップの詳細

### Step 1-2: Authentication & Firestore Database

**自動処理**: 
- ✓ firebase.json 設定確認
- ✓ firestore.rules デプロイ

**手動確認** (Firebase Console):
- [ ] Email/Password 有効化
- [ ] Google OAuth 設定
- [ ] Apple Sign-In 設定
- [ ] Collections 7個 作成
  ```
  - users
  - contents
  - courses
  - enrollments
  - progress
  - payments
  - notifications
  ```

### Step 3: Cloud Storage

**自動処理**:
```bash
# Bucket 作成（gsutil がある場合）
gsutil mb -l asia-northeast1 gs://safy-dev-japan-storage

# Folders 作成
gsutil cp "" gs://safy-dev-japan-storage/user-avatars/.keep
gsutil cp "" gs://safy-dev-japan-storage/content-assets/.keep
gsutil cp "" gs://safy-dev-japan-storage/certificates/.keep
gsutil cp "" gs://safy-dev-japan-storage/documents/.keep
```

### Step 4: Cloud Functions

**自動処理**:
```
📦 functions/src/index.ts
├─ submitQuizAttempt (クイズ採点・監査証跡)
├─ onReminderCreated (リマインド通知)
├─ checkModuleDeadlinesAndNotify (期限リマインダー)
├─ sendMonthlyReports (月次レポート送信)
└─ generateOriginalContent (AI コンテンツ生成)
```

**実行検証**:
```bash
firebase functions:log --project=safy-dev-japan
```

### Step 5: Cloud Messaging (FCM)

**手動確認** (Firebase Console):
- [ ] Cloud Messaging 有効化
- [ ] Server Key 取得
- [ ] Sender ID 取得
- [ ] Topics 3個 作成
  ```
  - announcements
  - course-updates
  - promotions
  ```

### Step 6: Analytics

**手動確認** (Firebase Console):
- [ ] Google Analytics for Firebase 有効化
- [ ] Custom Events 定義
  ```
  - content_started
  - content_completed
  - payment_completed
  - user_signup
  - user_login
  ```

---

## ✅ 確認チェックリスト

### ビルド確認
```bash
# Functions コンパイル確認
cd /home/user/project-033/functions
npm run build
ls -la lib/index.js
```

### デプロイ確認
```bash
# 最近のログを表示
firebase functions:log --project=safy-dev-japan --limit=20

# 特定関数のログ表示
firebase functions:log submitQuizAttempt --project=safy-dev-japan
```

### Firestore 確認
```bash
# Collections 一覧
gcloud firestore collections list --project=safy-dev-japan

# データ件数確認
gcloud firestore documents list --collection-ids=industries --project=safy-dev-japan
```

### Firebase Console 確認
1. https://console.firebase.google.com/project/safy-dev-japan
2. 以下を確認:
   - [ ] Authentication: 3 種類有効化
   - [ ] Firestore Database: Collections 表示
   - [ ] Cloud Storage: Bucket 存在
   - [ ] Functions: Deploy 完了
   - [ ] Cloud Messaging: Topics 表示
   - [ ] Analytics: 有効化

---

## 🧪 テスト実行手順

### 1. アプリビルド

```bash
cd /home/user/project-033
flutter pub get
flutter run
```

### 2. ログイン

```
Email: admin@example.com
Password: password123
```

### 3. 動作確認

- [ ] ホーム画面にコースが表示される
- [ ] コースを選択できる
- [ ] レッスンが再生される
- [ ] クイズが実行できる
- [ ] 修了証が生成される
- [ ] プッシュ通知が受け取れる

### 4. Firebase Console でログ確認

```bash
firebase functions:log --project=safy-dev-japan
```

**期待される出ログ**:
```
submitQuizAttempt: 得点 XX/100
sendMonthlyReports: Report sent to xxx@example.com
generateOriginalContent: Generated lesson for module_01
```

---

## 🆘 トラブルシューティング

### "firebase login" エラー

```bash
firebase logout
firebase login
firebase projects:list
```

### Functions デプロイ失敗

```bash
# デバッグモード実行
firebase deploy --project=safy-dev-japan --only functions --debug

# Node.js バージョン確認
node --version  # 20.x が必要

# npm 再インストール
cd functions
rm -rf node_modules package-lock.json
npm install --legacy-peer-deps
npm run build
```

### Firestore Collections が見えない

```bash
# Firebase Console で確認
https://console.firebase.google.com/project/safy-dev-japan/firestore

# または CLI で確認
gcloud firestore collections list --project=safy-dev-japan
```

### Cloud Storage Bucket 作成エラー

```bash
# gsutil がない場合は Firebase Console で手動作成
# または Google Cloud SDK インストール
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
```

---

## 📞 サポート

### ドキュメント参照
- [Firebase 公式ドキュメント](https://firebase.google.com/docs)
- [Cloud Functions ガイド](https://firebase.google.com/docs/functions)
- [Firestore セキュリティルール](https://firebase.google.com/docs/firestore/security/start)

### よくある質問

**Q. Sep 9 にすべてのステップが完了しない場合は?**
> A. Sep 15 (GATE 2) が hard deadline です。Sep 9-14 で完了を目指し、Firebase Console で手動確認しながら進めてください。

**Q. シークレット (API Keys) はどこに保管?**
> A. Firebase Functions Secrets Manager に自動保管されます。ローカルでは不要。

**Q. Firestore セキュリティルールが本番環境と異なる?**
> A. development は "Test mode"（すべて読み書き可）。本番環境では厳密なルール適用。

**Q. Functions のコストは?**
> A. 100万 invocation/月まで無料。development 環境では問題なし。

---

## 📅 次のステップ

### Sep 9 終了後
```bash
# Firestore セキュリティルール本番版テスト
firebase emulators:start --only firestore

# Flutter テストスイート実行
flutter test
```

### Sep 15 (GATE 2)
```bash
# 本番環境検証
firebase deploy --project=safy-production-primary --dry-run
```

### Oct 1 (Production Sprint)
```bash
# 本番環境デプロイ
firebase deploy --project=safy-production-primary --only functions
```

---

## 📝 実行ログ保存

すべてのセットアップログは以下に保存されます：

```bash
# ログファイル確認
cat firebase-setup-*.log

# ログクリア
rm firebase-setup-*.log
```

---

**最後更新**: 2026-09-05  
**次回確認**: 2026-09-09

