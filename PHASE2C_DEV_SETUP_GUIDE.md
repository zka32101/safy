# Phase 2c Stage 1 開発環境セットアップガイド

**対象**: Claude API チャットボット実装  
**バージョン**: Phase 2c Stage 1  
**作成日**: 2026-09-17  
**実行予定**: 2026-09-24 以降

---

## 目次

1. [環境要件](#環境要件)
2. [初期セットアップ](#初期セットアップ)
3. [Firebase プロジェクト設定](#firebase-プロジェクト設定)
4. [Claude API キーの取得](#claude-api-キーの取得)
5. [ローカル開発環境](#ローカル開発環境)
6. [テスト環境](#テスト環境)
7. [本番環境](#本番環境)
8. [トラブルシューティング](#トラブルシューティング)

---

## 環境要件

### 最小要件

```
Node.js: 18.x 以上
npm: 9.x 以上
Firebase CLI: 12.x 以上
Git: 2.x 以上
```

### 推奨スペック

```
OS: macOS 12+ / Ubuntu 20.04+ / Windows 11
RAM: 8GB 以上
ディスク: 10GB 以上（依存パッケージ・キャッシュ用）
ネットワーク: 10Mbps 以上
```

### アカウント・APIキー

```
- Google アカウント（Firebase プロジェクト管理）
- Claude API キー（Anthropic）
- GitHub アカウント（コード管理）
```

---

## 初期セットアップ

### Step 1: リポジトリクローン

```bash
cd ~/projects
git clone https://github.com/zka32101/safy.git
cd safy
```

### Step 2: ブランチ切り替え

```bash
# Phase 2c 実装用ブランチ
git checkout -b claude/phase2c-ai-tutor origin/claude/phase2b-learning-paths

# または既存ブランチを使用
git checkout claude/phase2c-ai-tutor
git pull origin claude/phase2c-ai-tutor
```

### Step 3: 依存パッケージインストール

```bash
# ルートディレクトリ
npm install

# Cloud Functions
cd functions
npm install
cd ..

# Flutter アプリ
flutter pub get
```

### Step 4: Node.js バージョン確認

```bash
node --version  # v18.x 以上
npm --version   # 9.x 以上
```

---

## Firebase プロジェクト設定

### Step 1: Firebase プロジェクト選択

```bash
firebase login

# プロジェクト一覧表示
firebase projects:list

# 使用プロジェクト設定
firebase use safy-prod
```

### Step 2: Firestore セットアップ

```bash
# Firestore のデータベースが存在することを確認
firebase firestore:indexes --list

# セキュリティルールをデプロイ（ドライラン）
firebase deploy --only firestore:rules --dry-run
```

### Step 3: Cloud Functions 設定

```bash
# Cloud Functions の環境変数設定
firebase functions:config:set claude.api_key="${CLAUDE_API_KEY}"

# 確認
firebase functions:config:get

# または .env.local で管理
echo "CLAUDE_API_KEY=sk-ant-v7-..." > functions/.env.local
```

### Step 4: Secret Manager 設定

```bash
# Google Cloud SDK へのログイン
gcloud auth login
gcloud config set project safy-prod

# Claude API キーを Secret Manager に保存
echo -n "sk-ant-v7-..." | gcloud secrets create claude-api-key --data-file=-

# または既存キーを更新
echo -n "sk-ant-v7-..." | gcloud secrets versions add claude-api-key --data-file=-

# アクセス確認
gcloud secrets get-iam-policy claude-api-key
```

### Step 5: Service Account 権限設定

```bash
# Firestore アクセス権限
gcloud projects add-iam-policy-binding safy-prod \
  --member=serviceAccount:safy-prod@appspot.gserviceaccount.com \
  --role=roles/datastore.user

# Secret Manager アクセス権限
gcloud projects add-iam-policy-binding safy-prod \
  --member=serviceAccount:safy-prod@appspot.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor
```

---

## Claude API キーの取得

### Step 1: Anthropic Console へアクセス

```
https://console.anthropic.com/
```

1. Anthropic アカウントにログイン
2. 「API Keys」セクションを開く
3. 「Create Key」をクリック

### Step 2: API キーを環境変数に設定

```bash
# .env.local に保存
echo "CLAUDE_API_KEY=sk-ant-v7-xxxxxxxxxxxxxx" >> functions/.env.local

# または ~/.bashrc に追加（グローバル設定）
echo "export CLAUDE_API_KEY='sk-ant-v7-xxxxxxxxxxxxxx'" >> ~/.bashrc
source ~/.bashrc
```

### Step 3: API キー検証

```bash
# Node.js で確認
cd functions
node -e "console.log(process.env.CLAUDE_API_KEY)"
```

### Step 4: API クォータ確認

```bash
# Anthropic Console で「Usage」セクションを確認
# - Monthly requests（月間リクエスト数）
# - Token usage（トークン使用量）
```

---

## ローカル開発環境

### Step 1: Firebase Emulator Suite セットアップ

```bash
# インストール
firebase setup:emulators:firestore

# Emulator Suite 起動
firebase emulators:start

# ブラウザ自動起動（http://localhost:4000）
firebase emulators:start --import=./test-data
```

### Step 2: Cloud Functions ローカル実行

```bash
cd functions

# ローカルでテスト
npm run test

# デバッグモード
firebase emulators:start --inspect-functions

# 特定の関数をテスト
npm run serve
```

### Step 3: Flutter アプリの実行

```bash
# デバッグモード
flutter run --dart-define=FIREBASE_PROJECT=safy-dev

# Web 版（開発時に便利）
flutter run -d web

# リリースビルド
flutter build web --release
```

### Step 4: IDE 設定（VS Code）

```json
// .vscode/launch.json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Emulator Debug",
      "type": "node",
      "request": "launch",
      "program": "${workspaceFolder}/functions/lib/index.js",
      "skipFiles": ["<node_internals>/**"]
    }
  ]
}
```

### Step 5: ホットリロード設定

```bash
# TypeScript ウォッチモード
cd functions
npm run watch

# Flutter ホットリロード
flutter run -d web  # Ctrl+R でリロード
```

---

## テスト環境

### Step 1: テストフレームワーク

```bash
# Cloud Functions テスト
cd functions
npm install --save-dev jest firebase-functions-test
npm install --save-dev @types/jest

# Flutter テスト
flutter test
```

### Step 2: サンプルテストコード

```typescript
// functions/src/index.test.ts
import * as functions from 'firebase-functions-test';
import * as admin from 'firebase-admin';

const wrapped = functions.wrap(require('./index').callAIChatbot);

describe('callAIChatbot', () => {
  beforeEach(() => {
    // テスト前処理
  });

  it('Claude API を呼び出してメッセージを返す', async () => {
    const data = {
      companyId: 'test-company',
      employeeId: 'test-user',
      message: 'テスト質問です'
    };

    const result = await wrapped(data, {
      auth: { uid: 'test-user' }
    });

    expect(result.message).toBeDefined();
    expect(result.tokenCount).toBeGreaterThan(0);
  });
});
```

### Step 3: テスト実行

```bash
# 全テスト実行
npm test

# 特定のテストのみ実行
npm test -- callAIChatbot

# カバレッジ測定
npm test -- --coverage
```

### Step 4: パフォーマンステスト

```bash
# レスポンス時間測定
npm run perf-test

# メモリ使用量測定
node --max_old_space_size=512 node_modules/.bin/jest
```

---

## 本番環境

### Step 1: 本番デプロイ前チェック

```bash
# ブランチ確認
git branch -a

# コミットがプッシュされているか確認
git log --oneline -5

# 変更されていないファイル確認
git status
```

### Step 2: Environment Variables 設定

```bash
# 本番用環境変数
firebase functions:config:set \
  claude.api_key="${CLAUDE_API_KEY_PROD}" \
  claude.model="claude-3-5-sonnet-20241022" \
  claude.max_tokens="1024" \
  rate_limit.user_per_minute="5" \
  rate_limit.company_per_minute="50"

# 確認
firebase functions:config:get
```

### Step 3: ドライランでテスト

```bash
# Firestore ルール ドライラン
firebase deploy --only firestore:rules --dry-run

# Cloud Functions ドライラン
firebase deploy --only functions --dry-run
```

### Step 4: デプロイ実行

```bash
# Firestore セキュリティルール
firebase deploy --only firestore:rules

# Cloud Functions
firebase deploy --only functions

# 複数リージョンをデプロイ
firebase deploy --only functions:callAIChatbot

# 進行状況確認
firebase functions:log --limit=50
```

### Step 5: 本番環境検証

```bash
# デプロイ後のロギング確認
firebase functions:log --limit=100

# パフォーマンス確認
curl -X POST https://asia-northeast1-safy-prod.cloudfunctions.net/callAIChatbot \
  -H "Authorization: Bearer ${ID_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "companyId": "test-company",
    "employeeId": "test-user",
    "message": "テスト質問"
  }'
```

### Step 6: ロールバック手順

```bash
# 前のバージョンに戻す（ブランチを切り替え）
git checkout origin/claude/phase2b-learning-paths

# 前のコード状態でデプロイ
firebase deploy --only functions

# または特定の時点のコミットにロールバック
git reset --hard <commit-hash>
firebase deploy
```

---

## トラブルシューティング

### 問題 1: Claude API キーが見つからない

```bash
# エラー: "Claude API キーの取得に失敗しました"

# 解決策 1: 環境変数の確認
echo $CLAUDE_API_KEY

# 解決策 2: Secret Manager の確認
gcloud secrets get-secret-version --secret="claude-api-key" latest

# 解決策 3: Local .env.local の確認
cat functions/.env.local

# 解決策 4: Firebase functions:config の確認
firebase functions:config:get
```

### 問題 2: Firebase Emulator が起動しない

```bash
# エラー: "Port 8080 already in use"

# 解決策 1: ポート変更
firebase emulators:start --firestore-port=8081

# 解決策 2: プロセス強制終了
lsof -i :8080  # プロセス確認
kill -9 <PID>  # 強制終了

# 解決策 3: 再インストール
firebase setup:emulators:firestore --force
```

### 問題 3: Cloud Functions デプロイが失敗

```bash
# エラー: "Deployment failed"

# 解決策 1: ビルド確認
cd functions && npm run build

# 解決策 2: ログ確認
firebase deploy --debug

# 解決策 3: Node.js バージョン確認
node --version  # 18.x 以上であることを確認

# 解決策 4: 依存パッケージ再インストール
rm -rf node_modules package-lock.json
npm install
```

### 問題 4: レート制限が機能しない

```bash
# Redis 接続エラー

# 解決策 1: Redis がインストール・起動しているか確認
redis-cli ping  # PONG が返ってくれば OK

# 解決策 2: Redis 起動
redis-server

# 解決策 3: 接続ポート確認
redis-cli -p 6379 ping
```

### 問題 5: テストが失敗する

```bash
# エラー: "Mock not set up"

# 解決策 1: Firestore モック確認
npm test -- --detectOpenHandles

# 解決策 2: テストタイムアウト増加
jest.setTimeout(10000);  // 10秒

# 解決策 3: 特定のテストのみ実行
npm test -- callAIChatbot.test.ts --verbose
```

---

## チェックリスト

### 開発環境セットアップ完了確認

- [ ] Node.js / npm インストール完了
- [ ] Firebase CLI ログイン完了
- [ ] Claude API キー取得・保存完了
- [ ] リポジトリクローン完了
- [ ] npm install 完了
- [ ] Firebase Emulator Suite 起動確認
- [ ] Cloud Functions ローカル実行確認
- [ ] ユニットテスト実行確認（成功）
- [ ] IDE 設定完了（VS Code など）

### テスト環境完了確認

- [ ] Firebase テストプロジェクト設定
- [ ] Firestore テストデータ準備
- [ ] Cloud Functions テスト実行確認
- [ ] 統合テスト実行確認
- [ ] パフォーマンステスト実行確認

### 本番環境デプロイ前確認

- [ ] 本番プロジェクト ID 確認
- [ ] Secret Manager キー設定確認
- [ ] ドライランデプロイ成功
- [ ] 本番環境ログ確認設定
- [ ] ロールバック手順確認
- [ ] バックアップ実施

---

## 参考リンク

- [Firebase Documentation](https://firebase.google.com/docs)
- [Claude API Documentation](https://docs.anthropic.com/claude/reference/claude-api-reference)
- [Google Cloud Functions](https://cloud.google.com/functions/docs)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/start)

---

**ステータス**: 📋 実装準備中  
**最終更新**: 2026-09-17  
**使用開始**: 2026-09-24（Phase 2c Stage 1 Week 1 開始時）
