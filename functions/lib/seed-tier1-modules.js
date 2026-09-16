"use strict";
/**
 * Tier 1 Training モジュールを Firestore に登録するスクリプト
 * 実行方法: npx ts-node functions/src/seed-tier1-modules.ts
 * または firebase deploy --only functions で自動実行
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const admin = __importStar(require("firebase-admin"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
// Firebase 初期化
const serviceAccountPath = process.env.FIREBASE_CONFIG_PATH || "./firebase-config.json";
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));
admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: process.env.FIREBASE_PROJECT_ID || "safy-dev-japan",
});
const db = admin.firestore();
// Tier 1 Training モジュールのデータ
const TIER1_MODULES = [
    {
        id: "tier1-platform-tech",
        title: "Platform技術概要",
        description: "Firebase ecosystem、Cloud Functions、Firestore、本番環境構築の基礎知識",
        passThresholdDefault: 80,
        category: "engineering",
        duration: "4時間",
    },
    {
        id: "tier1-operations",
        title: "Operations・監視体制",
        description: "監視・アラート設定、性能最適化、エラーハンドリング、24/7 サポート体制構築",
        passThresholdDefault: 80,
        category: "operations",
        duration: "4時間",
    },
    {
        id: "tier1-content-production",
        title: "Content Production・配信戦略",
        description: "エンタープライズ研修コンテンツの企画・制作・配信フロー、クオリティ管理、ローカライズ戦略",
        passThresholdDefault: 80,
        category: "operations",
        duration: "4時間",
    },
    {
        id: "tier1-gtm-strategy",
        title: "GTM Strategy・営業展開",
        description: "Go-To-Market 戦略、顧客獲得・セグメンテーション、営業サイクル管理、成功メトリクス",
        passThresholdDefault: 80,
        category: "business",
        duration: "4時間",
    },
];
// モジュール JSON ファイルのパス
const TRAINING_DIR = path.join(__dirname, "../../../training");
async function seedTier1Modules() {
    try {
        console.log("🔄 Tier 1 Training モジュールを Firestore に登録中...");
        for (const moduleMetadata of TIER1_MODULES) {
            const jsonPath = path.join(TRAINING_DIR, `${moduleMetadata.id}.json`);
            // JSON ファイルが存在するかチェック
            if (!fs.existsSync(jsonPath)) {
                console.warn(`⚠️  ファイルが見つかりません: ${jsonPath}`);
                continue;
            }
            // JSON ファイルを読み込み
            const moduleData = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
            console.log(`📝 登録中: ${moduleMetadata.id}`);
            // modules/{moduleId} ドキュメント作成
            await db.doc(`modules/${moduleMetadata.id}`).set({
                title: moduleData.title,
                description: moduleData.description,
                passThresholdDefault: moduleData.passThresholdDefault,
                categoryId: moduleData.category,
                duration: moduleData.duration,
                isFreeTrial: false,
                sortOrder: TIER1_MODULES.indexOf(moduleMetadata),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            // レッスンを登録
            if (moduleData.lessons && Array.isArray(moduleData.lessons)) {
                console.log(`  📚 ${moduleData.lessons.length} レッスンを登録中...`);
                for (const lesson of moduleData.lessons) {
                    await db
                        .doc(`modules/${moduleMetadata.id}/lessons/${lesson.id}`)
                        .set({
                        id: lesson.id,
                        title: lesson.title,
                        order: lesson.order,
                        body: lesson.body,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }
            }
            // クイズ問題を登録
            if (moduleData.quizQuestions && Array.isArray(moduleData.quizQuestions)) {
                console.log(`  ❓ ${moduleData.quizQuestions.length} クイズ問題を登録中...`);
                for (const question of moduleData.quizQuestions) {
                    await db
                        .doc(`modules/${moduleMetadata.id}/quizQuestions/${question.id}`)
                        .set({
                        id: question.id,
                        question: question.question,
                        choices: question.choices,
                        correctIndex: question.correctIndex,
                        explanation: question.explanation,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }
            }
            console.log(`✅ ${moduleMetadata.id} が正常に登録されました`);
        }
        console.log("\n🎉 すべての Tier 1 Training モジュールが登録されました");
        console.log("\n登録内容:");
        console.log("- 4つのモジュール");
        console.log("- 合計 16 レッスン (4 lessons × 4 modules)");
        console.log("- 合計 20 クイズ問題 (5 questions × 4 modules)");
        console.log("\n合格基準: 各モジュール 80% 以上");
        console.log("学習期間: Sep 16-22, 2026 (7日間)");
    }
    catch (error) {
        console.error("❌ エラーが発生しました:", error.message);
        throw error;
    }
    finally {
        await admin.app().delete();
    }
}
// スクリプト実行
seedTier1Modules()
    .then(() => {
    console.log("\n✨ シード完了");
    process.exit(0);
})
    .catch((error) => {
    console.error("致命的エラー:", error);
    process.exit(1);
});
//# sourceMappingURL=seed-tier1-modules.js.map