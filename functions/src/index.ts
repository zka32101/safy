/**
 * 安心企業研修Safy Cloud Functions
 *
 * 前提: Firebase Console本設定・`firebase deploy --only functions`実行後に有効化される。
 * ローカルではflutter analyze/testの対象外(Node.js/TypeScript側は別途 `npm run build` で検証)。
 *
 * 実装済み関数:
 *   - submitQuizAttempt: クイズ採点・監査証跡書き込み(QuizService.submitAttemptから呼ばれる)
 *   - onReminderCreated: 管理者の個別リマインド送信をトリガーにプッシュ通知を送る
 *   - checkModuleDeadlinesAndNotify: 受講期限が近い/過ぎた社員に毎日プッシュ通知する(定期実行)
 *   - sendMonthlyReports: 前月分の履修状況レポートをcontactEmail宛に毎月1日送信する(定期実行)
 *     ※SendGrid経由で直接送信する。デプロイ前に以下のSecretを設定すること:
 *       firebase functions:secrets:set SENDGRID_API_KEY
 *       firebase functions:secrets:set SENDGRID_FROM_EMAIL  (SendGridで送信元認証済みのアドレス)
 *     (Firebase Extensions「Trigger Email」は2027-03-31に廃止予定のため採用しない)
 *   - generateOriginalContent: プレミアムプラン向けオリジナルコンテンツ(レッスン+クイズ)を
 *     Claude APIでAI生成する(管理者向け、生成結果は保存前にクライアント側で確認・編集させる)。
 *     デプロイ前に以下のSecretを設定すること:
 *       firebase functions:secrets:set ANTHROPIC_API_KEY
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/v2";
import sgMail from "@sendgrid/mail";
import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import { z } from "zod";

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

const sendgridApiKey = defineSecret("SENDGRID_API_KEY");
const sendgridFromEmail = defineSecret("SENDGRID_FROM_EMAIL");
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// JST(UTC+9)固定。本アプリは現状JST圏のみを対象とするため、date-onlyの比較は
// すべてJSTの暦日基準で行う(サーバーのDateはUTC基準のため、そのまま日数差を
// 取るとFlutter側 DeadlineStatusEvaluator の日付のみ比較と最大1日ズレる)。
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/// [date]のJSTでの暦日(年月日)を、その暦日0時ちょうどを表すUTCミリ秒として返す。
function jstDateOnlyMs(date: Date): number {
  const jst = new Date(date.getTime() + JST_OFFSET_MS);
  return Date.UTC(jst.getUTCFullYear(), jst.getUTCMonth(), jst.getUTCDate());
}

// ─────────────────────────────────────────────
// 型(Flutter側のモデルと対応。Cloud Functions側は緩めのバリデーションに留める)
// ─────────────────────────────────────────────
interface QuizQuestionDoc {
  correctIndex: number;
}

interface CompanyDoc {
  name?: string;
  customPassThreshold?: Record<string, number>;
  moduleDeadlines?: Record<string, admin.firestore.Timestamp>;
  contractedHeadcount?: number;
  contactEmail?: string;
}

interface ModuleDoc {
  passThresholdDefault?: number;
}

interface EmployeeDoc {
  fcmToken?: string;
  displayName?: string;
}

// ─────────────────────────────────────────────
// submitQuizAttempt: クイズ採点・QuizAttempt/CompletionCertificate書き込み
// 改ざん防止のためクライアントから直接書き込ませず、ここで正式なスコアを再計算する。
// ─────────────────────────────────────────────
export const submitQuizAttempt = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "サインインが必要です");
  }

  const { companyId, employeeId, moduleId, selectedAnswers } = request.data as {
    companyId?: string;
    employeeId?: string;
    moduleId?: string;
    selectedAnswers?: number[];
  };

  if (!companyId || !employeeId || !moduleId || !Array.isArray(selectedAnswers)) {
    throw new HttpsError("invalid-argument", "companyId/employeeId/moduleId/selectedAnswersが必要です");
  }
  // Employeeドキュメント名は必ずauth.uidと一致させる方式(EmployeeService参照)なので、
  // 他人になりすましてクイズ結果を書き込めないようにここで検証する。
  if (auth.uid !== employeeId) {
    throw new HttpsError("permission-denied", "本人以外のクイズ結果は送信できません");
  }

  const [companySnap, employeeSnap, globalModuleSnap] = await Promise.all([
    db.doc(`companies/${companyId}`).get(),
    db.doc(`companies/${companyId}/employees/${employeeId}`).get(),
    db.doc(`modules/${moduleId}`).get(),
  ]);

  if (!companySnap.exists) {
    throw new HttpsError("not-found", "会社情報が見つかりません");
  }
  // employeeIdはauth.uidと一致するだけでなく、実際にこのcompanyId配下に
  // 所属している(=正規の招待フローでjoinしている)ことも確認する。これが無いと
  // 認証済みユーザーが無関係な他社companyIdを指定してクイズ結果を捏造できてしまう。
  if (!employeeSnap.exists) {
    throw new HttpsError("permission-denied", "この会社に所属する社員が見つかりません");
  }

  const company = companySnap.data() as CompanyDoc;

  // moduleIdはグローバルモジュール、または(プレミアムプランの)会社独自のオリジナル
  // モジュールのいずれか。オリジナルモジュールの場合はcustomModules配下から解決する。
  // グローバルモジュールの場合も、会社が追加したオリジナル問題(moduleExtensions)が
  // あればクライアント側の表示順(既存→追加)と揃えて合算する。
  let passThresholdDefault = 80;
  let correctIndexes: number[];

  if (globalModuleSnap.exists) {
    const module = globalModuleSnap.data() as ModuleDoc;
    passThresholdDefault = module.passThresholdDefault ?? 80;

    const [baseQuestionsSnap, extensionQuestionsSnap] = await Promise.all([
      db.collection(`modules/${moduleId}/quizQuestions`).get(),
      db.collection(`companies/${companyId}/moduleExtensions/${moduleId}/quizQuestions`).get(),
    ]);
    if (baseQuestionsSnap.empty && extensionQuestionsSnap.empty) {
      throw new HttpsError("failed-precondition", "この研修にはまだクイズ問題が登録されていません");
    }
    correctIndexes = [
      ...baseQuestionsSnap.docs.map((d) => (d.data() as QuizQuestionDoc).correctIndex),
      ...extensionQuestionsSnap.docs.map((d) => (d.data() as QuizQuestionDoc).correctIndex),
    ];
  } else {
    const customModuleSnap = await db.doc(`companies/${companyId}/customModules/${moduleId}`).get();
    if (!customModuleSnap.exists) {
      throw new HttpsError("not-found", "研修モジュールが見つかりません");
    }
    const customModule = customModuleSnap.data() as { passThresholdDefault?: number };
    passThresholdDefault = customModule.passThresholdDefault ?? 80;

    const questionsSnap = await db
      .collection(`companies/${companyId}/customModules/${moduleId}/quizQuestions`)
      .get();
    if (questionsSnap.empty) {
      throw new HttpsError("failed-precondition", "この研修にはまだクイズ問題が登録されていません");
    }
    correctIndexes = questionsSnap.docs.map((d) => (d.data() as QuizQuestionDoc).correctIndex);
  }

  const correctCount = correctIndexes.reduce(
    (count, correct, i) => (selectedAnswers[i] === correct ? count + 1 : count),
    0
  );
  const score = Math.round((correctCount / correctIndexes.length) * 100);
  const thresholdApplied = company.customPassThreshold?.[moduleId] ?? passThresholdDefault;
  const passed = score >= thresholdApplied;
  const answeredAt = admin.firestore.FieldValue.serverTimestamp();

  const attemptRef = db.collection(`companies/${companyId}/quizAttempts`).doc();
  await attemptRef.set({
    employeeId,
    moduleId,
    score,
    passed,
    thresholdApplied,
    selectedAnswers,
    answeredAt,
  });

  if (passed) {
    const certificateRef = db.collection(`companies/${companyId}/certificates`).doc();
    await certificateRef.set({
      employeeId,
      companyId,
      moduleId,
      score,
      thresholdApplied,
      issuedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // callableの戻り値はJSONとしてシリアライズされるため、answeredAtはミリ秒数値で返す
  // (Flutter側QuizAttempt.fromMapのparseFirestoreDateTimeがnum/Timestamp両対応)。
  return {
    attemptId: attemptRef.id,
    employeeId,
    moduleId,
    score,
    passed,
    thresholdApplied,
    selectedAnswers,
    answeredAt: Date.now(),
  };
});

// ─────────────────────────────────────────────
// onReminderCreated: 管理者の個別リマインド送信(ReminderService.sendReminder)を
// トリガーにプッシュ通知を送る。
// ─────────────────────────────────────────────
export const onReminderCreated = onDocumentCreated(
  "companies/{companyId}/reminders/{reminderId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const { companyId } = event.params;
    const { employeeId } = snapshot.data() as { employeeId?: string };
    if (!employeeId) return;

    const employeeSnap = await db.doc(`companies/${companyId}/employees/${employeeId}`).get();
    const employee = employeeSnap.data() as EmployeeDoc | undefined;
    if (!employee?.fcmToken) {
      logger.info(`fcmToken未登録のためリマインド通知をスキップ: ${employeeId}`);
      return;
    }

    await messaging.send({
      token: employee.fcmToken,
      notification: {
        title: "研修のリマインド",
        body: "未受講の研修があります。安心企業研修Safyでご確認ください。",
      },
    });
  }
);

// ─────────────────────────────────────────────
// checkModuleDeadlinesAndNotify: 受講期限が近い(3日以内)/過ぎた社員に毎日通知する。
// Firebase Console設定完了後、Cloud Schedulerが自動的にこの関数を毎日呼び出す。
// ─────────────────────────────────────────────
const REMINDER_WINDOW_DAYS = 3;

export const checkModuleDeadlinesAndNotify = onSchedule(
  { schedule: "every day 09:00", timeZone: "Asia/Tokyo" },
  async () => {
    const companiesSnap = await db.collection("companies").get();

    for (const companyDoc of companiesSnap.docs) {
      const company = companyDoc.data() as CompanyDoc;
      const deadlines = company.moduleDeadlines ?? {};
      if (Object.keys(deadlines).length === 0) continue;

      const companyId = companyDoc.id;
      const [employeesSnap, enrollmentsSnap] = await Promise.all([
        db.collection(`companies/${companyId}/employees`).get(),
        db.collection(`companies/${companyId}/enrollments`).get(),
      ]);

      const completedByEmployeeModule = new Set(
        enrollmentsSnap.docs
          .filter((d) => d.data().status === "completed")
          .map((d) => `${d.data().employeeId}_${d.data().moduleId}`)
      );

      for (const [moduleId, dueDateTimestamp] of Object.entries(deadlines)) {
        const dueDate = dueDateTimestamp.toDate();
        // Flutter側 DeadlineStatusEvaluator と同様、JSTの暦日のみで比較する
        // (時刻・タイムゾーンを含めたミリ秒差だと期限日当日に1日早くoverdue判定されてしまう)。
        const daysRemaining = Math.round(
          (jstDateOnlyMs(dueDate) - jstDateOnlyMs(new Date())) / DAY_MS
        );
        // リマインド期間より先、または大幅に過ぎた古い期限は対象外(通知の送りすぎを防ぐ)
        if (daysRemaining > REMINDER_WINDOW_DAYS || daysRemaining < -30) continue;

        const statusLabel = daysRemaining < 0 ? "期限を過ぎています" : "期限が近づいています";

        for (const employeeDoc of employeesSnap.docs) {
          const employee = employeeDoc.data() as EmployeeDoc;
          if (!employee.fcmToken) continue;
          if (completedByEmployeeModule.has(`${employeeDoc.id}_${moduleId}`)) continue;

          try {
            await messaging.send({
              token: employee.fcmToken,
              notification: {
                title: "受講期限のお知らせ",
                body: `未受講の研修があります。${statusLabel}。安心企業研修Safyでご確認ください。`,
              },
            });
          } catch (error) {
            logger.warn(`通知送信に失敗しました employeeId=${employeeDoc.id}`, error);
          }
        }
      }
    }
  }
);

// ─────────────────────────────────────────────
// sendMonthlyReports: 毎月1日9時(JST)に、contactEmailを設定している会社へ
// 前月分の履修状況レポートをSendGrid経由で直接メール送信する。
// ─────────────────────────────────────────────
export const sendMonthlyReports = onSchedule(
  {
    schedule: "1 of month 09:00",
    timeZone: "Asia/Tokyo",
    secrets: [sendgridApiKey, sendgridFromEmail],
  },
  async () => {
    sgMail.setApiKey(sendgridApiKey.value());
    const fromEmail = sendgridFromEmail.value();

    // 「前月分」レポートなので、実行時点(当月1日)ではなく前月のJST暦日区間で集計する。
    const jstNow = new Date(Date.now() + JST_OFFSET_MS);
    const periodStart = new Date(
      Date.UTC(jstNow.getUTCFullYear(), jstNow.getUTCMonth() - 1, 1) - JST_OFFSET_MS
    );
    const periodEnd = new Date(
      Date.UTC(jstNow.getUTCFullYear(), jstNow.getUTCMonth(), 1) - JST_OFFSET_MS
    );
    const periodStartJst = new Date(periodStart.getTime() + JST_OFFSET_MS);
    const reportMonthLabel = `${periodStartJst.getUTCFullYear()}年${periodStartJst.getUTCMonth() + 1}月`;

    const companiesSnap = await db.collection("companies").get();

    for (const companyDoc of companiesSnap.docs) {
      const company = companyDoc.data() as CompanyDoc;
      const contactEmail = company.contactEmail?.trim();
      if (!contactEmail) continue;

      const companyId = companyDoc.id;
      const [employeesSnap, enrollmentsSnap] = await Promise.all([
        db.collection(`companies/${companyId}/employees`).get(),
        db.collection(`companies/${companyId}/enrollments`).get(),
      ]);

      const totalEmployees = employeesSnap.size;
      const completedByEmployee = new Map<string, number>();
      for (const doc of enrollmentsSnap.docs) {
        const data = doc.data();
        if (data.status !== "completed") continue;
        const completedAt = (data.completedAt as admin.firestore.Timestamp | undefined)?.toDate();
        if (!completedAt || completedAt < periodStart || completedAt >= periodEnd) continue;
        const employeeId = data.employeeId as string;
        completedByEmployee.set(employeeId, (completedByEmployee.get(employeeId) ?? 0) + 1);
      }
      const employeesWithProgress = completedByEmployee.size;

      try {
        await sgMail.send({
          to: contactEmail,
          from: fromEmail,
          subject: `【安心企業研修Safy】${reportMonthLabel} 履修状況レポート`,
          text:
            `${company.name ?? ""} 様\n\n` +
            `${reportMonthLabel}時点の履修状況をお知らせします。\n\n` +
            `対象社員数: ${totalEmployees}名\n` +
            `${reportMonthLabel}中に1件以上の研修を完了した社員数: ${employeesWithProgress}名\n\n` +
            `詳細はアプリの「レポート出力」画面からPDF/CSVでご確認いただけます。\n\n` +
            `安心企業研修Safy`,
        });
      } catch (error) {
        logger.warn(`月次レポートメール送信に失敗しました companyId=${companyId}`, error);
      }
    }
  }
);

// ─────────────────────────────────────────────
// generateOriginalContent: プレミアムプラン向けオリジナルコンテンツAI生成
// ─────────────────────────────────────────────
const GENERATION_MODES = ["extend", "create"] as const;
type GenerationMode = (typeof GENERATION_MODES)[number];

const THEME_MAX_LENGTH = 200;

export const generateOriginalContent = onCall(
  { secrets: [anthropicApiKey], timeoutSeconds: 120 },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "サインインが必要です");
    }

    const { companyId, mode, theme, categoryId, targetModuleId } = request.data as {
      companyId?: string;
      mode?: GenerationMode;
      theme?: string;
      categoryId?: string;
      targetModuleId?: string;
    };

    if (!companyId || !mode || !theme) {
      throw new HttpsError("invalid-argument", "companyId/mode/themeが必要です");
    }
    if (!GENERATION_MODES.includes(mode)) {
      throw new HttpsError("invalid-argument", "modeはextendまたはcreateである必要があります");
    }
    if (theme.trim().length === 0 || theme.length > THEME_MAX_LENGTH) {
      throw new HttpsError("invalid-argument", `テーマは1〜${THEME_MAX_LENGTH}文字で入力してください`);
    }
    if (mode === "create" && !categoryId) {
      throw new HttpsError("invalid-argument", "新規モジュール作成にはcategoryIdが必要です");
    }
    if (mode === "extend" && !targetModuleId) {
      throw new HttpsError("invalid-argument", "既存モジュール追加にはtargetModuleIdが必要です");
    }

    // 本人が実際にそのcompanyIdの管理者であることを確認する(他社のオリジナルコンテンツを
    // 汚染できないよう、submitQuizAttemptと同様にcompanyId所属をサーバー側で検証する)。
    const employeeSnap = await db.doc(`companies/${companyId}/employees/${auth.uid}`).get();
    const employee = employeeSnap.data() as { role?: string } | undefined;
    if (!employeeSnap.exists || employee?.role !== "admin") {
      throw new HttpsError("permission-denied", "この会社の管理者のみ実行できます");
    }

    // プレミアムプランの契約状態はサーバー側で再確認する(クライアントの自己申告を信用しない)。
    const subscriptionSnap = await db
      .doc(`companies/${companyId}/subscriptions/company_${companyId}`)
      .get();
    const subscription = subscriptionSnap.data() as
      | { status?: string; premiumTier?: string; expiresAt?: admin.firestore.Timestamp }
      | undefined;
    const isActive =
      subscription?.status === "active" &&
      (!subscription.expiresAt || subscription.expiresAt.toDate() > new Date());
    const tier = isActive ? subscription?.premiumTier ?? "none" : "none";
    const hasAccess =
      mode === "create" ? tier === "moduleCreation" : tier === "moduleExtension" || tier === "moduleCreation";
    if (!hasAccess) {
      throw new HttpsError(
        "permission-denied",
        mode === "create"
          ? "新規モジュール作成にはプレミアムプラン(上位)の契約が必要です"
          : "オリジナルコンテンツ追加にはプレミアムプランの契約が必要です"
      );
    }

    let targetModuleContext = "";
    if (mode === "extend" && targetModuleId) {
      const moduleSnap = await db.doc(`modules/${targetModuleId}`).get();
      if (!moduleSnap.exists) {
        throw new HttpsError("not-found", "対象のモジュールが見つかりません");
      }
      const moduleData = moduleSnap.data() as { title?: string; description?: string };
      targetModuleContext =
        `追加先の既存モジュール:「${moduleData.title ?? ""}」\n` +
        `既存モジュールの説明: ${moduleData.description ?? ""}\n` +
        "このモジュールの補足として自然につながる、重複しない内容にしてください。\n\n";
    }

    const lessonCount = mode === "create" ? 3 : 2;
    const quizCount = mode === "create" ? 6 : 4;

    const lessonSchema = z.object({
      title: z.string().describe("レッスンのタイトル(20文字程度)"),
      body: z
        .string()
        .describe("レッスン本文。200〜400文字程度で、具体的な職場での事例を交えて解説する"),
    });
    const quizQuestionSchema = z.object({
      question: z.string().describe("クイズの問題文"),
      choices: z.array(z.string()).length(4).describe("4択の選択肢(正解を1つ含む)"),
      correctIndex: z.number().int().min(0).max(3).describe("正解の選択肢のインデックス(0始まり)"),
      explanation: z.string().describe("なぜその選択肢が正解か、他が不正解かの解説"),
    });

    const schema =
      mode === "create"
        ? z.object({
            moduleTitle: z.string().describe("モジュールのタイトル(20文字程度)"),
            moduleDescription: z.string().describe("モジュールの説明文(50〜100文字程度)"),
            lessons: z.array(lessonSchema).length(lessonCount),
            quizQuestions: z.array(quizQuestionSchema).length(quizCount),
          })
        : z.object({
            lessons: z.array(lessonSchema).length(lessonCount),
            quizQuestions: z.array(quizQuestionSchema).length(quizCount),
          });

    const anthropic = new Anthropic({ apiKey: anthropicApiKey.value() });

    const prompt =
      "あなたは中小企業向け教育アプリ「安心企業研修Safy」のコンテンツ作成者です。\n" +
      "以下のテーマについて、社員研修用のレッスンとクイズ問題を作成してください。\n\n" +
      `テーマ: ${theme}\n\n` +
      targetModuleContext +
      `レッスン${lessonCount}本(導入→具体例→まとめ・行動指針、の流れが望ましい)と、` +
      `クイズ${quizCount}問(4択・正解1つ・解説付き)を作成してください。\n` +
      "実際の職場で起こりうる具体的な事例を交え、専門用語は平易に説明してください。\n" +
      "クイズは本文の内容を踏まえた設問にし、正解の位置(0〜3)は偏らせず、" +
      "不正解の選択肢も「もっともらしいが誤り」であるようにしてください。";

    let parsed: z.infer<typeof schema>;
    try {
      const response = await anthropic.beta.messages.parse({
        model: "claude-opus-5",
        max_tokens: 8000,
        messages: [{ role: "user", content: prompt }],
        output_format: betaZodOutputFormat(schema),
      });
      if (!response.parsed_output) {
        throw new Error("parsed_output is null");
      }
      parsed = response.parsed_output;
    } catch (error) {
      logger.error(`AIコンテンツ生成に失敗しました companyId=${companyId}`, error);
      throw new HttpsError("internal", "AIによるコンテンツ生成に失敗しました。もう一度お試しください");
    }

    return parsed;
  }
);

/// レベル診断の完了・学習パス推奨
export const completeLevelDiagnostic = onCall(async (request) => {
  const {
    companyId,
    employeeId,
    answers,
    totalScore,
    averageScore,
    recommendedLevel,
  } = request.data;

  try {
    if (!companyId || !employeeId || !recommendedLevel) {
      throw new HttpsError(
        "invalid-argument",
        "必須項目が不足しています"
      );
    }

    const diagnosticId = db.collection("diagnostics").doc().id;
    const now = admin.firestore.FieldValue.serverTimestamp();

    // 診断結果を保存
    await db
      .collection("companies")
      .doc(companyId)
      .collection("employeeDiagnostics")
      .doc(diagnosticId)
      .set({
        id: diagnosticId,
        employeeId,
        answers: answers || {},
        totalScore: totalScore || 0,
        averageScore: averageScore || 0,
        recommendedLevel,
        completedAt: now,
        createdAt: now,
      });

    // 従業員のスキルレベルを更新
    await db
      .collection("companies")
      .doc(companyId)
      .collection("employees")
      .doc(employeeId)
      .update({
        skillLevel: recommendedLevel,
        lastDiagnosticAt: now,
        updatedAt: now,
      });

    logger.info(
      `レベル診断完了: ${diagnosticId} (従業員: ${employeeId}, レベル: ${recommendedLevel})`
    );

    // 分析イベント記録
    await db.collection("analytics_events").doc().set({
      event: "diagnostic_completed",
      companyId,
      employeeId,
      recommendedLevel,
      averageScore,
      timestamp: now,
    });

    return {
      success: true,
      diagnosticId,
      recommendedLevel,
      message: "スキルレベル診断が完了しました",
    };
  } catch (error: any) {
    logger.error(`レベル診断に失敗: ${error.message}`, error);
    throw new HttpsError(
      "internal",
      `レベル診断に失敗しました: ${error.message}`
    );
  }
});
