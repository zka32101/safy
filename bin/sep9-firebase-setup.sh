#!/bin/bash
# Sep 9 Firebase マスターセットアップスクリプト
# Sep 9 Firebase Master Setup Script
# すべてのステップを自動実行 (手動確認ポイント付き)
#
# 使用方法:
#   ./bin/sep9-firebase-setup.sh [project-id] [options]
#
# 例:
#   ./bin/sep9-firebase-setup.sh safy-dev-japan
#   ./bin/sep9-firebase-setup.sh safy-dev-japan --skip-seed
#   ./bin/sep9-firebase-setup.sh safy-dev-japan --functions-only

set -e

PROJECT_ID="${1:-safy-dev-japan}"
SKIP_SEED=false
FUNCTIONS_ONLY=false
BUILD_ONLY=false

shift 2>/dev/null
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-seed) SKIP_SEED=true; shift ;;
    --functions-only) FUNCTIONS_ONLY=true; shift ;;
    --build-only) BUILD_ONLY=true; shift ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# HEADER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  🚀 Sep 9 Firebase マスターセットアップ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📋 実行予定:"
echo "  Project ID: $PROJECT_ID"
echo "  Region: asia-northeast1"
echo ""

if [ "$FUNCTIONS_ONLY" = true ]; then
  echo "  ✓ Functions デプロイのみ実行"
  echo ""
elif [ "$BUILD_ONLY" = true ]; then
  echo "  ✓ Functions ビルドのみ実行"
  echo ""
else
  echo "  ✓ Step 1: 前提条件チェック"
  echo "  ✓ Step 2: Functions ビルド"
  echo "  ✓ Step 3: Functions デプロイ"
  if [ "$SKIP_SEED" = false ]; then
    echo "  ✓ Step 4: Firestore シード投入"
  fi
  echo "  ✓ Step 5: 最終確認"
  echo ""
fi

read -p "  → 続行しますか? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "⚠️  キャンセルしました"
  exit 0
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Functions ビルド & デプロイ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📦 Step: Firebase Functions${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$FUNCTIONS_ONLY" = true ]; then
  # Functions デプロイのみ
  echo "📤 Functions デプロイのみ実行"
  echo ""
  bash "$SCRIPT_DIR/deploy-functions.sh" "$PROJECT_ID" --deploy-only || {
    echo -e "${RED}❌ Functions デプロイ失敗${NC}"
    exit 1
  }
elif [ "$BUILD_ONLY" = true ]; then
  # ビルドのみ
  echo "🔨 Functions ビルドのみ実行"
  echo ""
  bash "$SCRIPT_DIR/deploy-functions.sh" "$PROJECT_ID" --build-only || {
    echo -e "${RED}❌ Functions ビルド失敗${NC}"
    exit 1
  }
else
  # 通常: ビルド & デプロイ
  bash "$SCRIPT_DIR/deploy-functions.sh" "$PROJECT_ID" || {
    echo -e "${RED}❌ Functions デプロイ失敗${NC}"
    exit 1
  }
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Firestore シード投入（--functions-only 時はスキップ）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$FUNCTIONS_ONLY" = false ] && [ "$BUILD_ONLY" = false ] && [ "$SKIP_SEED" = false ]; then
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}🌱 Step: Firestore シード投入${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  bash "$SCRIPT_DIR/seed-firestore.sh" "$PROJECT_ID" || {
    echo -e "${YELLOW}⚠️  Firestore シード投入スキップ${NC}"
  }

  echo ""
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 最終確認
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$FUNCTIONS_ONLY" = false ] && [ "$BUILD_ONLY" = false ]; then
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}✅ Step: 最終確認${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  echo "📋 確認チェックリスト:"
  echo ""
  echo "  [ ] Firebase Console でログイン可能か確認"
  echo "      → https://console.firebase.google.com/project/$PROJECT_ID"
  echo ""
  echo "  [ ] Functions ログでエラーがないか確認"
  echo "      → firebase functions:log --project=$PROJECT_ID"
  echo ""
  echo "  [ ] Firestore Collections が作成されているか確認"
  echo "      - industries"
  echo "      - modules"
  echo "      - companies/{companyId}/employees"
  echo "      - companies/{companyId}/enrollments"
  echo ""
  echo "  [ ] Cloud Storage Bucket が作成されているか確認"
  echo "      → $PROJECT_ID-storage"
  echo ""
  echo "  [ ] Analytics が有効化されているか確認"
  echo "      → Firebase Console > Analytics"
  echo ""

  echo "🧪 テスト実行:"
  echo ""
  echo "  1. アプリビルド & 起動:"
  echo "     $ cd $PROJECT_ROOT"
  echo "     $ flutter run"
  echo ""
  echo "  2. ログイン:"
  echo "     - Email: admin@example.com"
  echo "     - Password: password123"
  echo ""
  echo "  3. 動作確認:"
  echo "     - コースが表示される"
  echo "     - クイズが実行できる"
  echo "     - 修了証が生成される"
  echo ""
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 完了
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✨ Firebase セットアップ完了!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📚 関連ドキュメント:"
echo "  - Firebase 設定: https://firebase.google.com/docs/projects/learn-more"
echo "  - Functions: https://firebase.google.com/docs/functions"
echo "  - Firestore: https://firebase.google.com/docs/firestore"
echo ""
echo "🔗 便利なコマンド:"
echo "  $ firebase functions:log --project=$PROJECT_ID                  # Functions ログ表示"
echo "  $ firebase deploy --project=$PROJECT_ID                        # 全体デプロイ"
echo "  $ flutter run                                                    # アプリ実行"
echo ""
echo "📞 トラブルシューティング:"
echo "  $ firebase deploy --project=$PROJECT_ID --only functions --debug"
echo ""
