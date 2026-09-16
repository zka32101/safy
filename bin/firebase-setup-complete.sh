#!/bin/bash
# Firebase 全体セットアップスクリプト (Sep 9実行用)
# Complete Firebase Setup Script for Sep 9 Execution
#
# 使用方法:
#   ./bin/firebase-setup-complete.sh [project-id] [environment]
#
# 例:
#   ./bin/firebase-setup-complete.sh safy-dev-japan dev

set -e  # エラー発生時は即座に終了

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. 初期化 & 引数チェック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PROJECT_ID="${1:-safy-dev-japan}"
ENVIRONMENT="${2:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SETUP_LOG="${PROJECT_ROOT}/firebase-setup-$(date +%Y%m%d-%H%M%S).log"

echo "🚀 Firebase セットアップ開始"
echo "  Project ID: $PROJECT_ID"
echo "  Environment: $ENVIRONMENT"
echo "  Log: $SETUP_LOG"
echo ""

{

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. 前提条件チェック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "📋 前提条件チェック..."

if ! command -v firebase &> /dev/null; then
  echo "❌ Firebase CLI が見つかりません"
  echo "   インストール: npm install -g firebase-tools"
  exit 1
fi

if ! command -v gcloud &> /dev/null; then
  echo "⚠️  gcloud CLI が見つかりません (オプション)"
  echo "   インストール: https://cloud.google.com/sdk/docs/install"
fi

firebase --version
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. Step 3: Authentication セットアップ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "✓ Step 3: Authentication セットアップ (確認のみ)"
echo "  ℹ️  Firebase Console で以下が有効化されていることを確認:"
echo "     - Email/Password Authentication"
echo "     - Google OAuth"
echo "     - Apple Sign-In"
echo ""

# Step 3 は Firebase Console で手動設定が必要（デモンストレーション表示）
read -p "  → Step 3 完了しましたか? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "  ⚠️  Step 3 スキップ"
fi
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. Step 4: Firestore Database セットアップ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "✓ Step 4: Firestore Database セットアップ"
echo "  - Firestore セキュリティルール デプロイ"

if [ -f "$PROJECT_ROOT/firestore.rules" ]; then
  echo "    📄 firestore.rules 検出"

  # セキュリティルールをデプロイ
  firebase deploy --project="$PROJECT_ID" --only firestore:rules || {
    echo "    ⚠️  セキュリティルール デプロイ失敗"
    echo "    💡 Firebase Console で手動確認してください"
  }
else
  echo "    ⚠️  firestore.rules が見つかりません"
fi

echo "  ℹ️  次の Collections は Firebase Console で以下のように作成してください:"
echo "     1. users - ユーザー情報"
echo "     2. contents - コンテンツ"
echo "     3. courses - コース管理"
echo "     4. enrollments - 受講情報"
echo "     5. progress - 進捗情報"
echo "     6. payments - 支払い情報"
echo "     7. notifications - 通知ログ"
echo ""

read -p "  → Step 4 (Collections 作成) 完了しましたか? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "  ⚠️  Step 4 スキップ"
fi
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. Step 5: Cloud Storage セットアップ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "✓ Step 5: Cloud Storage セットアップ"

BUCKET_NAME="${PROJECT_ID}-storage"
echo "  - Bucket: $BUCKET_NAME"
echo "  - Region: asia-northeast1"

# Bucket 作成を試みる（既存の場合はスキップ）
if command -v gsutil &> /dev/null; then
  if ! gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
    echo "    作成中..."
    gsutil mb -l asia-northeast1 "gs://$BUCKET_NAME" || {
      echo "    ⚠️  Bucket 作成失敗（既存の可能性）"
    }
  else
    echo "    既存の Bucket を使用"
  fi

  # Folders 作成
  echo "  - Folders 作成中..."
  for folder in user-avatars content-assets certificates documents; do
    echo "" | gsutil -h "Cache-Control: no-cache" cp - "gs://$BUCKET_NAME/$folder/.keep" 2>/dev/null || true
  done
else
  echo "  ⚠️  gsutil が見つかりません (Cloud Storage セットアップはスキップ)"
  echo "  ℹ️  Firebase Console で以下を作成してください:"
  echo "     - Bucket: $BUCKET_NAME"
  echo "     - Folders: /user-avatars, /content-assets, /certificates, /documents"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. Step 6: Firebase Functions デプロイ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "✓ Step 6: Firebase Functions デプロイ準備"

if [ -d "$PROJECT_ROOT/functions" ]; then
  echo "  📦 Functions ディレクトリ検出"

  # TypeScript コンパイル
  echo "  - TypeScript コンパイル中..."
  cd "$PROJECT_ROOT/functions"
  npm run build || {
    echo "  ❌ ビルド失敗"
    exit 1
  }
  cd "$PROJECT_ROOT"

  echo "  ✓ ビルド成功"
  echo ""
  echo "  ℹ️  デプロイ前に以下のシークレットを設定してください:"
  echo "     $ firebase functions:secrets:set SENDGRID_API_KEY --project=$PROJECT_ID"
  echo "     $ firebase functions:secrets:set SENDGRID_FROM_EMAIL --project=$PROJECT_ID"
  echo "     $ firebase functions:secrets:set ANTHROPIC_API_KEY --project=$PROJECT_ID"
  echo ""

  read -p "  → シークレット設定完了しましたか? (y/n) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  デプロイ中..."
    firebase deploy --project="$PROJECT_ID" --only functions || {
      echo "  ⚠️  デプロイ失敗。Firebase Console で手動確認してください"
    }
  else
    echo "  ⚠️  Step 6 スキップ (シークレット設定が必要)"
  fi
else
  echo "  ⚠️  functions ディレクトリが見つかりません"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. Step 7: FCM セットアップ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "✓ Step 7: Firebase Cloud Messaging (FCM) セットアップ"
echo "  ℹ️  以下を Firebase Console で実行してください:"
echo "     1. Project Settings → Cloud Messaging タブ"
echo "     2. Server Key と Sender ID を取得"
echo "     3. Topics を作成:"
echo "        - announcements"
echo "        - course-updates"
echo "        - promotions"
echo ""

read -p "  → Step 7 完了しましたか? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "  ⚠️  Step 7 スキップ"
fi
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 8. Step 8: Analytics セットアップ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "✓ Step 8: Google Analytics for Firebase セットアップ"
echo "  ℹ️  Firebase Console で以下を実行してください:"
echo "     1. Google Analytics for Firebase を有効化"
echo "     2. Custom Events を定義:"
echo "        - content_started"
echo "        - content_completed"
echo "        - payment_completed"
echo "        - user_signup"
echo "        - user_login"
echo ""

read -p "  → Step 8 完了しましたか? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "  ⚠️  Step 8 スキップ"
fi
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 9. セットアップ完了
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Firebase セットアップ完了!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 セットアップサマリー:"
echo "  Project ID: $PROJECT_ID"
echo "  Environment: $ENVIRONMENT"
echo "  Region: asia-northeast1"
echo ""
echo "🔗 確認リンク:"
echo "  - Firebase Console: https://console.firebase.google.com/project/$PROJECT_ID"
echo "  - Cloud Console: https://console.cloud.google.com/welcome?project=$PROJECT_ID"
echo ""
echo "📝 ログ保存: $SETUP_LOG"
echo ""

} 2>&1 | tee -a "$SETUP_LOG"

echo "✨ セットアップ準備完了。次のステップ:"
echo "   1. 上記の確認リンクで Firebase Console を開く"
echo "   2. 手動確認が必要な項目を完了"
echo "   3. flutter run で アプリが Firebase と接続することを確認"
echo ""
