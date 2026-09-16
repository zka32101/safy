/**
 * Tier 2/3 認定試験データの Firestore 登録スクリプト
 * 実行: npx ts-node functions/src/seed-exams.ts
 */

import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";

// Firebase 初期化
const serviceAccountPath = path.join(__dirname, "../serviceAccountKey.json");
if (!fs.existsSync(serviceAccountPath)) {
  console.error(
    "serviceAccountKey.json が見つかりません。Firebase Console から取得してください。"
  );
  process.exit(1);
}

const serviceAccount = JSON.parse(
  fs.readFileSync(serviceAccountPath, "utf8")
);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

interface ExamData {
  id: string;
  title: string;
  description: string;
  category: string;
  duration: number;
  passThreshold: number;
  tier: number;
  createdAt: string;
  questions: Array<{
    id: string;
    order: number;
    text: string;
    options: string[];
    correctOption: number;
  }>;
}

async function seedExams() {
  try {
    console.log("🚀 Tier 2/3 認定試験データ登録開始...");

    const examFiles = ["tier2-exam.json", "tier3-exam.json"];

    for (const filename of examFiles) {
      const filePath = path.join(__dirname, "../training", filename);

      if (!fs.existsSync(filePath)) {
        console.warn(`⚠️ ${filename} が見つかりません。スキップします。`);
        continue;
      }

      const examData: ExamData = JSON.parse(fs.readFileSync(filePath, "utf8"));

      // 試験メタデータを登録
      const examMetadata = {
        id: examData.id,
        title: examData.title,
        description: examData.description,
        category: examData.category,
        duration: examData.duration,
        passThreshold: examData.passThreshold,
        tier: examData.tier,
        questionCount: examData.questions.length,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db.collection("exams").doc(examData.id).set(examMetadata);

      console.log(`✅ 試験メタデータ登録: ${examData.id}`);

      // 試験問題を登録
      for (const question of examData.questions) {
        await db
          .collection("exams")
          .doc(examData.id)
          .collection("questions")
          .doc(question.id)
          .set({
            id: question.id,
            order: question.order,
            text: question.text,
            options: question.options,
            correctOption: question.correctOption,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
      }

      console.log(
        `✅ 問題登録完了: ${examData.id} (${examData.questions.length}問)`
      );
    }

    console.log("✅ Tier 2/3 認定試験データ登録完了");
    process.exit(0);
  } catch (error: any) {
    console.error("❌ エラー:", error.message);
    process.exit(1);
  }
}

seedExams();
