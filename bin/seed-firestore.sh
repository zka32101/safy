#!/bin/bash
# Firestore 初期データシード投入スクリプト
# Seed Firestore with initial data for testing
#
# 使用方法:
#   ./bin/seed-firestore.sh [project-id] [--dry-run]
#
# 例:
#   ./bin/seed-firestore.sh safy-dev-japan
#   ./bin/seed-firestore.sh safy-dev-japan --dry-run

set -e

PROJECT_ID="${1:-safy-dev-japan}"
DRY_RUN=false

if [[ "$2" == "--dry-run" ]]; then
  DRY_RUN=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SEED_SCRIPT="$PROJECT_ROOT/bin/seed_firestore.dart"

echo "🌱 Firestore シード投入開始"
echo "  Project ID: $PROJECT_ID"
echo "  Dry Run: $DRY_RUN"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. 前提条件チェック
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "📋 前提条件チェック..."

if ! command -v dart &> /dev/null; then
  echo "❌ Dart が見つかりません"
  echo "   Flutter を使用している場合: flutter pub global run seed_firestore"
  exit 1
fi

if ! command -v firebase &> /dev/null; then
  echo "❌ Firebase CLI が見つかりません"
  exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. Firebase ユーザー認証確認
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "🔐 Firebase 認証確認中..."
if ! firebase auth:export /tmp/firebase-auth-test.json --project="$PROJECT_ID" &>/dev/null; then
  echo "⚠️  Firebase プロジェクトにアクセスできません"
  echo "   実行: firebase login"
  exit 1
fi
echo "  ✓ 認証成功"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. シード投入計画表示
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "📊 投入予定データ:"
echo ""
echo "  Collection: industries (業界マスタ)"
echo "    - 10+ 業界データ"
echo ""
echo "  Collection: modules (研修モジュール)"
echo "    - 18 コース"
echo "    - 各コース配下: lessons, quizQuestions"
echo ""
echo "  Collection: companies/{companyId}/employees (テストユーザー)"
echo "    - Admin ユーザー (ID: admin-test-001)"
echo "    - Employee ユーザー (ID: employee-test-001～003)"
echo ""
echo "  Collection: companies/{companyId}/enrollments (受講情報)"
echo "    - 3 件のテスト受講登録"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. 確認
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "⚠️  注意:"
echo "  - 既存データは上書きされません（新規作成のみ）"
echo "  - 実行には Google Cloud SDK の認証が必要です"
echo "  - 実行時間: 2-5 分"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "🧪 DRY RUN モード (実際には投入しません)"
  read -p "  → 続行しますか? (y/n) " -n 1 -r
else
  read -p "  → Firestore に投入しますか? (y/n) " -n 1 -r
fi

echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "⚠️  キャンセルしました"
  exit 0
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. シード投入実行
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "🌱 シード投入実行中..."

if [ ! -f "$SEED_SCRIPT" ]; then
  echo "⚠️  bin/seed_firestore.dart が見つかりません"
  echo "   以下の方法で実行してください:"
  echo ""
  echo "   方法1: Dart スクリプト実行"
  echo "     $ dart run bin/seed_firestore.dart"
  echo ""
  echo "   方法2: Flutter ビルド完了後"
  echo "     $ flutter pub run"
  echo ""
  exit 1
fi

cd "$PROJECT_ROOT"

# Environment 変数設定
export FIREBASE_PROJECT_ID="$PROJECT_ID"
export FIRESTORE_DRY_RUN="$DRY_RUN"

# Dart スクリプト実行
dart run bin/seed_firestore.dart || {
  echo ""
  echo "❌ シード投入失敗"
  echo "   ログを確認: cat firestore-seed.log"
  exit 1
}

echo ""
echo "✅ Firestore シード投入完了!"
echo ""
echo "📊 確認方法:"
echo "   1. Firebase Console を開く:"
echo "      https://console.firebase.google.com/project/$PROJECT_ID/firestore"
echo "   2. Collections タブで以下を確認:"
echo "      - industries: 10+ 件"
echo "      - modules: 18 件"
echo "      - companies/*/employees: テストユーザー"
echo ""
echo "🧪 テスト手順:"
echo "   1. flutter run で アプリを起動"
echo "   2. ログイン: admin@example.com / password123"
echo "   3. コースが表示されることを確認"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. 統計情報取得
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "📈 データ統計:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v gcloud &> /dev/null; then
  echo "  (Google Cloud SDK で統計情報を取得中...)"
  # gcloud firestore documents list --collection-ids=industries --project="$PROJECT_ID" 2>/dev/null | wc -l || true
else
  echo "  💡 詳細統計は Firebase Console で確認してください"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
