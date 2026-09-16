#!/bin/bash
# Firebase Functions デプロイスクリプト
# Deploy Firebase Functions with automatic secret management
#
# 使用方法:
#   ./bin/deploy-functions.sh [project-id] [--set-secrets] [--build-only] [--deploy-only]
#
# 例:
#   ./bin/deploy-functions.sh safy-dev-japan --set-secrets
#   ./bin/deploy-functions.sh safy-dev-japan --build-only
#   ./bin/deploy-functions.sh safy-dev-japan --deploy-only

set -e

PROJECT_ID="${1:-safy-dev-japan}"
BUILD_ONLY=false
DEPLOY_ONLY=false
SET_SECRETS=false

# オプション解析
shift
while [[ $# -gt 0 ]]; do
  case $1 in
    --build-only) BUILD_ONLY=true; shift ;;
    --deploy-only) DEPLOY_ONLY=true; shift ;;
    --set-secrets) SET_SECRETS=true; shift ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FUNCTIONS_DIR="$PROJECT_ROOT/functions"

echo "🚀 Firebase Functions デプロイ開始"
echo "  Project ID: $PROJECT_ID"
echo "  Functions Dir: $FUNCTIONS_DIR"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. TypeScript コンパイル
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$DEPLOY_ONLY" = false ]; then
  echo "📦 Step 1: TypeScript コンパイル"

  cd "$FUNCTIONS_DIR"

  if [ ! -f "package.json" ]; then
    echo "❌ functions/package.json が見つかりません"
    exit 1
  fi

  # npm install（必要な場合）
  if [ ! -d "node_modules" ]; then
    echo "  - node_modules インストール中..."
    npm install --legacy-peer-deps || {
      echo "  ⚠️  npm install 失敗"
      exit 1
    }
  fi

  # TypeScript コンパイル
  echo "  - TypeScript コンパイル中..."
  npm run build || {
    echo "  ❌ ビルド失敗"
    echo "     実行: npm run build"
    exit 1
  }

  if [ ! -d "lib" ] || [ ! -f "lib/index.js" ]; then
    echo "  ❌ ビルド成功したが lib/index.js が生成されていません"
    exit 1
  fi

  echo "  ✓ ビルド成功"
  echo ""

  cd "$PROJECT_ROOT"
fi

# Build Only の場合はここで終了
if [ "$BUILD_ONLY" = true ]; then
  echo "✨ ビルド完了。デプロイはスキップしました。"
  exit 0
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. シークレット設定（オプション）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$SET_SECRETS" = true ]; then
  echo "🔐 Step 2: Secrets 設定"
  echo "  ℹ️  以下を入力してください（スキップ可）："
  echo ""

  read -p "  → SendGrid API Key: " SENDGRID_API_KEY
  if [ -n "$SENDGRID_API_KEY" ]; then
    echo "    設定中..."
    firebase functions:secrets:set SENDGRID_API_KEY --project="$PROJECT_ID" <<< "$SENDGRID_API_KEY" || {
      echo "    ⚠️  設定失敗"
    }
  fi

  read -p "  → SendGrid From Email: " SENDGRID_FROM_EMAIL
  if [ -n "$SENDGRID_FROM_EMAIL" ]; then
    echo "    設定中..."
    firebase functions:secrets:set SENDGRID_FROM_EMAIL --project="$PROJECT_ID" <<< "$SENDGRID_FROM_EMAIL" || {
      echo "    ⚠️  設定失敗"
    }
  fi

  read -p "  → Anthropic API Key: " ANTHROPIC_API_KEY
  if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "    設定中..."
    firebase functions:secrets:set ANTHROPIC_API_KEY --project="$PROJECT_ID" <<< "$ANTHROPIC_API_KEY" || {
      echo "    ⚠️  設定失敗"
    }
  fi

  echo ""
else
  echo "⚠️  シークレット設定スキップ"
  echo "  💡 以下を手動実行してください:"
  echo "     $ firebase functions:secrets:set SENDGRID_API_KEY --project=$PROJECT_ID"
  echo "     $ firebase functions:secrets:set SENDGRID_FROM_EMAIL --project=$PROJECT_ID"
  echo "     $ firebase functions:secrets:set ANTHROPIC_API_KEY --project=$PROJECT_ID"
  echo ""
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. Firebase Functions デプロイ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "📤 Step 3: Firebase Functions デプロイ"
echo "  Project: $PROJECT_ID"
echo "  Region: asia-northeast1"
echo ""

read -p "  → デプロイを実行しますか? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "  デプロイ中... (数分かかる場合があります)"
  echo ""

  firebase deploy --project="$PROJECT_ID" --only functions || {
    echo ""
    echo "❌ デプロイ失敗"
    echo "   トラブルシューティング:"
    echo "   1. firebase login で認証確認"
    echo "   2. Project ID の確認: firebase projects:list"
    echo "   3. 詳細: firebase deploy --project=$PROJECT_ID --only functions --debug"
    exit 1
  }

  echo ""
  echo "✅ Functions デプロイ完了!"
  echo ""
  echo "🔗 確認:"
  echo "   Firebase Console: https://console.firebase.google.com/project/$PROJECT_ID/functions"
  echo "   Logs: firebase functions:log --project=$PROJECT_ID"
  echo ""
else
  echo "⚠️  デプロイをキャンセルしました"
  exit 0
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. デプロイ後のログ確認
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "📋 最近のログ (直近 10行):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
firebase functions:log --project="$PROJECT_ID" --limit=10 || true
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "✨ Firebase Functions デプロイ完了!"
echo ""
echo "📝 次のステップ:"
echo "   1. flutter run で アプリを起動"
echo "   2. Cloud Functions ログで エラーがないか確認"
echo "   3. submitQuizAttempt など各関数の動作確認"
echo ""
