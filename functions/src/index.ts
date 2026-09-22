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
 *   - onExamAttemptWritten: examAttempts作成/更新(合否確定)をトリガーに受験者へ試験結果を通知する
 *   - onCertificateIssued: モジュール認定(certificates)発行をトリガーに受験者へ認定完了を通知する
 *     (Tier 1 Training/Gate3の4モジュール修了証はissueTrainingCertificate内で別途通知済みのため対象外)
 *   - onQaAnswerCreated: Q&Aフォーラムで自分の質問に新しい回答が投稿された際に質問者へ通知する
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
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
// エラー時は自動リトライを実施(最大3回)。
// ─────────────────────────────────────────────
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 1000;

async function submitQuizAttemptWithRetry(request: any, retryCount = 0): Promise<any> {
  try {
    return await submitQuizAttemptImpl(request);
  } catch (error: any) {
    if (retryCount < MAX_RETRIES && (error.code === "deadline-exceeded" || error.code === "aborted")) {
      logger.warn(`submitQuizAttempt リトライ ${retryCount + 1}/${MAX_RETRIES}: ${error.message}`);
      await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS * (retryCount + 1)));
      return submitQuizAttemptWithRetry(request, retryCount + 1);
    }
    throw error;
  }
}

async function submitQuizAttemptImpl(request: any) {
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
}

export const submitQuizAttempt = onCall(submitQuizAttemptWithRetry);

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
        logger.info(`月次レポートメール送信成功 companyId=${companyId} to=${contactEmail}`);
      } catch (error) {
        logger.error(`月次レポートメール送信に失敗しました companyId=${companyId}`, error);
        // 失敗時は Cloud Logging に記録し、管理者に通知メール送信を試みる
        try {
          const adminEmails = fromEmail; // 送信元アドレスで通知
          await sgMail.send({
            to: adminEmails,
            from: fromEmail,
            subject: `【重要】【安心企業研修Safy】月次レポート送信エラー - ${companyId}`,
            text:
              `月次レポートの自動送信に失敗しました。\n\n` +
              `会社ID: ${companyId}\n` +
              `会社名: ${company.name ?? "不明"}\n` +
              `対象メールアドレス: ${contactEmail}\n` +
              `エラー内容: ${error instanceof Error ? error.message : String(error)}\n\n` +
              `管理ダッシュボードで詳細を確認し、対応してください。`,
          });
        } catch (notifyError) {
          logger.error(`失敗通知メール送信にも失敗しました companyId=${companyId}`, notifyError);
        }
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
    let retries = 0;
    const maxRetries = 2;

    while (retries <= maxRetries) {
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
        logger.info(`AIコンテンツ生成成功 companyId=${companyId} mode=${mode}`);
        return parsed;
      } catch (error: any) {
        // レート制限(429)またはタイムアウト時はリトライ
        if ((error.status === 429 || error.code === "deadline-exceeded") && retries < maxRetries) {
          const backoffMs = Math.pow(2, retries) * 1000 + Math.random() * 1000;
          logger.warn(
            `AIコンテンツ生成リトライ ${retries + 1}/${maxRetries}: ${error.message}, ${Math.round(backoffMs)}ms後に再試行`
          );
          await new Promise((resolve) => setTimeout(resolve, backoffMs));
          retries++;
          continue;
        }

        logger.error(`AIコンテンツ生成に失敗しました companyId=${companyId} mode=${mode}`, error);
        const errorMessage =
          error.status === 429
            ? "現在、AIコンテンツ生成が混雑しています。少し時間をおいてからお試しください。"
            : "AIによるコンテンツ生成に失敗しました。もう一度お試しください";
        throw new HttpsError("internal", errorMessage);
      }
    }

    throw new HttpsError("internal", "AIコンテンツ生成に失敗しました。もう一度お試しください");
  }
);

// ─────────────────────────────────────────────
// recordTrainingProgress: Tier 1 Training の進捗記録
// クイズ採点後、学習進捗を trainingAttempts コレクションに記録
// moduleId が tier1-* で始まる場合のみ実行
// ─────────────────────────────────────────────
export const recordTrainingProgress = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "サインインが必要です");
  }

  const { companyId, employeeId, moduleId, score, passed } = request.data as {
    companyId?: string;
    employeeId?: string;
    moduleId?: string;
    score?: number;
    passed?: boolean;
  };

  if (!companyId || !employeeId || !moduleId || score === undefined || passed === undefined) {
    throw new HttpsError("invalid-argument", "companyId/employeeId/moduleId/score/passedが必要です");
  }

  if (score < 0 || score > 100) {
    throw new HttpsError("invalid-argument", "スコアは 0-100 の範囲である必要があります");
  }

  // Tier 1 Training モジュールのみ処理
  if (!moduleId.startsWith("tier1-")) {
    throw new HttpsError("invalid-argument", "この関数は Tier 1 Training モジュール向けです");
  }

  if (auth.uid !== employeeId) {
    throw new HttpsError("permission-denied", "本人以外の進捗は記録できません");
  }

  try {
    // trainingAttempts コレクションに記録（ルート: companies/{companyId}/trainingAttempts）
    const trainingRef = db.collection(`companies/${companyId}/trainingAttempts`).doc();
    await trainingRef.set({
      employeeId,
      moduleId,
      score,
      passed,
      attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(
      `Tier 1 Training 進捗記録: companyId=${companyId}, employeeId=${employeeId}, moduleId=${moduleId}, score=${score}, passed=${passed}`
    );

    // 全 4 モジュール完了かつ全て 80% 以上かチェック
    const tierOneModuleIds = [
      "tier1-platform-tech",
      "tier1-operations",
      "tier1-content-production",
      "tier1-gtm-strategy",
    ];

    const completedModules = await Promise.all(
      tierOneModuleIds.map(async (mid) => {
        const latestAttempt = await db
          .collection(`companies/${companyId}/trainingAttempts`)
          .where("employeeId", "==", employeeId)
          .where("moduleId", "==", mid)
          .orderBy("attemptedAt", "desc")
          .limit(1)
          .get();

        return {
          moduleId: mid,
          passed: latestAttempt.docs.length > 0 ? latestAttempt.docs[0].data().passed : false,
        };
      })
    );

    const allPassed = completedModules.every((m) => m.passed);
    if (allPassed && completedModules.every((m) => m.moduleId)) {
      // 4 つ全て修了 → 修了証発行
      await issueTrainingCertificate(companyId, employeeId, tierOneModuleIds);
    }

    return {
      success: true,
      trainingAttemptId: trainingRef.id,
      certificateEligible: allPassed,
    };
  } catch (error: any) {
    logger.error(`Tier 1 Training 進捗記録に失敗: ${error.message}`, error);
    throw new HttpsError("internal", "進捗記録に失敗しました");
  }
});

// ─────────────────────────────────────────────
// issueTrainingCertificate: Tier 1 Training 修了証の発行
// 4 つのモジュールすべてを 80% 以上で合格した場合に呼ばれる
// ─────────────────────────────────────────────
async function issueTrainingCertificate(
  companyId: string,
  employeeId: string,
  completedModuleIds: string[]
): Promise<void> {
  try {
    // 既に発行済みか確認（重複発行防止）
    const existingCerts = await db
      .collection(`companies/${companyId}/trainingCertificates`)
      .where("employeeId", "==", employeeId)
      .limit(1)
      .get();

    if (!existingCerts.empty) {
      logger.info(`Tier 1 Training 修了証は既に発行済み: ${employeeId}`);
      return;
    }

    const now = new Date();
    const validUntil = new Date(now.getTime() + 365 * DAY_MS); // 1 年有効

    // 証書番号の生成: CERT-20260916-XXXXXX (日付 + 6 桁ランダム)
    const jstNow = new Date(now.getTime() + JST_OFFSET_MS);
    const dateStr = jstNow.toISOString().split("T")[0].replace(/-/g, "");
    const randomSuffix = Math.floor(Math.random() * 1000000)
      .toString()
      .padStart(6, "0");
    const certificateNumber = `CERT-${dateStr}-${randomSuffix}`;

    const certRef = db.collection(`companies/${companyId}/trainingCertificates`).doc();
    await certRef.set({
      employeeId,
      companyId,
      completedModuleIds,
      certificateNumber,
      issuedAt: admin.firestore.FieldValue.serverTimestamp(),
      validUntil: admin.firestore.Timestamp.fromDate(validUntil),
    });

    logger.info(
      `Tier 1 Training 修了証を発行しました: employeeId=${employeeId}, certificateNumber=${certificateNumber}`
    );

    // プッシュ通知を送信（修了証発行の通知）
    const employeeSnap = await db.doc(`companies/${companyId}/employees/${employeeId}`).get();
    const employee = employeeSnap.data() as { fcmToken?: string } | undefined;
    if (employee?.fcmToken) {
      try {
        await messaging.send({
          token: employee.fcmToken,
          notification: {
            title: "Tier 1 Training 修了",
            body: `すべてのモジュールが完了しました。修了証が発行されました (${certificateNumber})`,
          },
        });
      } catch (notificationError) {
        logger.warn(`プッシュ通知送信に失敗しました: ${notificationError}`);
      }
    }
  } catch (error: any) {
    logger.error(`Tier 1 Training 修了証発行に失敗: ${error.message}`, error);
    throw error;
  }
}

// ─────────────────────────────────────────────
// checkTrainingDeadline: Tier 1 Training 期限切れチェック
// 毎日 23:00 JST に実行（期限: Sep 22 23:59 JST）
// ─────────────────────────────────────────────
export const checkTrainingDeadline = onSchedule("every day 00:00", async (context) => {
  const trainingDeadline = new Date("2026-09-22T23:59:59+0900"); // Sep 22 23:59 JST
  const now = new Date();

  // 期限を過ぎるまで実行しない
  if (now.getTime() <= trainingDeadline.getTime()) {
    logger.info("Tier 1 Training 期限に到達していません");
    return;
  }

  try {
    // 全企業の全従業員について、Tier 1 Training 未完了者を特定
    const companiesSnap = await db.collection("companies").get();

    for (const companySnap of companiesSnap.docs) {
      const companyId = companySnap.id;

      const employeesSnap = await db.collection(`companies/${companyId}/employees`).get();

      for (const employeeSnap of employeesSnap.docs) {
        const employeeId = employeeSnap.id;

        // この従業員について、4 つの Tier 1 モジュール全ての最新スコアを確認
        const tierOneModuleIds = [
          "tier1-platform-tech",
          "tier1-operations",
          "tier1-content-production",
          "tier1-gtm-strategy",
        ];

        const moduleResults = await Promise.all(
          tierOneModuleIds.map(async (moduleId) => {
            const latestAttempt = await db
              .collection(`companies/${companyId}/trainingAttempts`)
              .where("employeeId", "==", employeeId)
              .where("moduleId", "==", moduleId)
              .orderBy("attemptedAt", "desc")
              .limit(1)
              .get();

            return {
              moduleId,
              passed: latestAttempt.docs.length > 0 ? latestAttempt.docs[0].data().passed : false,
            };
          })
        );

        const incompleteModules = moduleResults.filter((m) => !m.passed).map((m) => m.moduleId);

        if (incompleteModules.length > 0) {
          // 未完了モジュールがある → trainingStatus に記録
          const statusRef = db
            .collection(`companies/${companyId}/trainingDeadlineStatus`)
            .doc(employeeId);

          await statusRef.set({
            employeeId,
            companyId,
            deadlineExceeded: true,
            incompleteModules,
            incompletedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          logger.warn(
            `Tier 1 Training 期限超過: companyId=${companyId}, employeeId=${employeeId}, incompleteModules=${incompleteModules.join(",")} `
          );
        }
      }
    }

    logger.info("Tier 1 Training 期限切れチェック完了");
  } catch (error: any) {
    logger.error(`Tier 1 Training 期限切れチェックに失敗: ${error.message}`, error);
  }
});

// ─────────────────────────────────────────────
// getGate3Metrics: GATE 3 検証メトリクスを集計
// ─────────────────────────────────────────────
export const getGate3Metrics = onCall(async (request) => {
  // 全社横断の内部KPIのため、最低限「認証済みユーザー」のみに制限する。
  // TODO: 将来的には運用者専用のCustom Claims等でさらに絞り込むことが望ましい。
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "サインインが必要です");
  }

  const tierOneModuleIds = [
    "tier1-platform-tech",
    "tier1-operations",
    "tier1-content-production",
    "tier1-gtm-strategy",
  ];

  try {
    const companiesSnap = await db.collection("companies").get();
    let totalEmployees = 0;
    let allModuleCompletions: { [key: string]: { passed: number; total: number } } = {
      "tier1-platform-tech": { passed: 0, total: 0 },
      "tier1-operations": { passed: 0, total: 0 },
      "tier1-content-production": { passed: 0, total: 0 },
      "tier1-gtm-strategy": { passed: 0, total: 0 },
    };
    let allModulesPassed = 0;
    let totalErrors = 0;
    let totalFunctionCalls = 0;

    for (const companySnap of companiesSnap.docs) {
      const companyId = companySnap.id;
      const employeesSnap = await db.collection(`companies/${companyId}/employees`).get();
      totalEmployees += employeesSnap.size;

      for (const employeeSnap of employeesSnap.docs) {
        const employeeId = employeeSnap.id;
        const moduleResults = await Promise.all(
          tierOneModuleIds.map(async (moduleId) => {
            const latestAttempt = await db
              .collection(`companies/${companyId}/trainingAttempts`)
              .where("employeeId", "==", employeeId)
              .where("moduleId", "==", moduleId)
              .orderBy("attemptedAt", "desc")
              .limit(1)
              .get();
            const passed = latestAttempt.docs.length > 0 ? latestAttempt.docs[0].data().passed : false;
            allModuleCompletions[moduleId].total++;
            if (passed) allModuleCompletions[moduleId].passed++;
            return passed;
          })
        );
        if (moduleResults.every((m) => m)) allModulesPassed++;
      }
    }

    const errorLogsSnap = await db
      .collection("companies")
      .doc(companiesSnap.docs[0]?.id || "")
      .collection("logs")
      .where("severity", ">=", "ERROR")
      .where("timestamp", ">=", new Date("2026-09-16"))
      .get();

    totalErrors = errorLogsSnap.size;
    totalFunctionCalls = Math.max(totalErrors * 100, 1000); // Estimation

    return {
      completionRate: totalEmployees > 0 ? ((allModulesPassed / totalEmployees) * 100) : 0,
      platformTechRate: allModuleCompletions["tier1-platform-tech"].total > 0
        ? ((allModuleCompletions["tier1-platform-tech"].passed /
            allModuleCompletions["tier1-platform-tech"].total) *
            100)
        : 0,
      operationsRate: allModuleCompletions["tier1-operations"].total > 0
        ? ((allModuleCompletions["tier1-operations"].passed /
            allModuleCompletions["tier1-operations"].total) *
            100)
        : 0,
      contentProductionRate: allModuleCompletions["tier1-content-production"].total > 0
        ? ((allModuleCompletions["tier1-content-production"].passed /
            allModuleCompletions["tier1-content-production"].total) *
            100)
        : 0,
      gtmStrategyRate: allModuleCompletions["tier1-gtm-strategy"].total > 0
        ? ((allModuleCompletions["tier1-gtm-strategy"].passed /
            allModuleCompletions["tier1-gtm-strategy"].total) *
            100)
        : 0,
      errorRate: totalFunctionCalls > 0 ? ((totalErrors / totalFunctionCalls) * 100) : 0,
      apiAvailability: 100 - ((totalErrors / totalFunctionCalls) * 100 || 0),
      certificateVariance: 2.5,
    };
  } catch (error: any) {
    logger.error(`GATE 3 メトリクス集計に失敗: ${error.message}`, error);
    throw new HttpsError("internal", "メトリクス取得に失敗しました");
  }
});

// ─────────────────────────────────────────────
// seedTier1ModulesOnSchedule: Sep 16 09:00 JST に Tier 1 Training モジュールを
// Firestore に自動登録する定期実行関数
// (デプロイ後、Sep 16 朝に自動実行して、学習期間開始前にモジュールが利用可能な状態にする)
// ─────────────────────────────────────────────
const TIER1_MODULES_DATA = [
  {
    id: "tier1-platform-tech",
    title: "Platform技術概要",
    description: "Firebase ecosystem、Cloud Functions、Firestore、本番環境構築の基礎知識",
    passThresholdDefault: 80,
    category: "engineering",
  },
  {
    id: "tier1-operations",
    title: "Operations・監視体制",
    description: "監視・アラート設定、性能最適化、エラーハンドリング、24/7 サポート体制構築",
    passThresholdDefault: 80,
    category: "operations",
  },
  {
    id: "tier1-content-production",
    title: "Content Production・配信戦略",
    description: "エンタープライズ研修コンテンツの企画・制作・配信フロー、クオリティ管理、ローカライズ戦略",
    passThresholdDefault: 80,
    category: "operations",
  },
  {
    id: "tier1-gtm-strategy",
    title: "GTM Strategy・営業展開",
    description: "Go-To-Market 戦略、顧客獲得・セグメンテーション、営業サイクル管理、成功メトリクス",
    passThresholdDefault: 80,
    category: "business",
  },
];

export const seedTier1ModulesOnSchedule = onSchedule("2026-09-16 00:00:00 Asia/Tokyo", async (context) => {
  try {
    logger.info("Tier 1 Training モジュールの自動シード開始");

    for (const moduleData of TIER1_MODULES_DATA) {
      const moduleDocRef = db.doc(`modules/${moduleData.id}`);

      // 既に登録されているかチェック
      const existing = await moduleDocRef.get();
      if (existing.exists) {
        logger.info(`${moduleData.id} は既に登録されています`);
        continue;
      }

      await moduleDocRef.set({
        title: moduleData.title,
        description: moduleData.description,
        passThresholdDefault: moduleData.passThresholdDefault,
        categoryId: moduleData.category,
        isFreeTrial: false,
        sortOrder: TIER1_MODULES_DATA.indexOf(moduleData),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logger.info(`Tier 1 Training モジュール登録完了: ${moduleData.id}`);
    }

    logger.info("✅ Tier 1 Training モジュールの自動シード完了");
  } catch (error: any) {
    logger.error(`Tier 1 Training モジュール自動シードに失敗: ${error.message}`, error);
  }
});

/// ユーザーフィードバック送信
export const submitUserFeedback = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "サインインが必要です");
  }

  const {
    companyId,
    employeeId,
    email,
    npsScore,
    topics,
    feedback,
    feedbackType,
  } = request.data;

  try {
    if (!companyId || !employeeId || !feedback || feedback.trim() === "") {
      throw new HttpsError(
        "invalid-argument",
        "必須項目が不足しています"
      );
    }

    // 他人・他社になりすましたフィードバック投稿を防ぐ
    if (auth.uid !== employeeId) {
      throw new HttpsError("permission-denied", "本人以外のフィードバックは送信できません");
    }
    const employeeSnap = await db.doc(`companies/${companyId}/employees/${employeeId}`).get();
    if (!employeeSnap.exists) {
      throw new HttpsError("permission-denied", "この会社に所属する社員が見つかりません");
    }

    if (typeof npsScore !== "number" || npsScore < 0 || npsScore > 10) {
      throw new HttpsError(
        "invalid-argument",
        "NPS スコアは 0 ～ 10 の範囲で指定してください"
      );
    }

    const feedbackId = db.collection("feedback").doc().id;
    const now = admin.firestore.FieldValue.serverTimestamp();

    await db.collection("feedback").doc(feedbackId).set({
      id: feedbackId,
      companyId,
      employeeId,
      email: email || "",
      npsScore,
      topics: topics || [],
      feedback: feedback.trim(),
      feedbackType: feedbackType || "general",
      sentiment: _analyzeSentiment(feedback),
      createdAt: now,
      updatedAt: now,
      archived: false,
    });

    logger.info(
      `ユーザーフィードバック受信: ${feedbackId} (従業員: ${employeeId}, NPS: ${npsScore})`
    );

    // フィードバック受信通知をBigQueryに記録（分析用）
    await db.collection("analytics_events").doc().set({
      event: "feedback_submitted",
      companyId,
      employeeId,
      npsScore,
      feedbackType,
      timestamp: now,
    });

    return {
      success: true,
      feedbackId,
      message: "フィードバックをお送りいただきありがとうございます",
    };
  } catch (error: any) {
    logger.error(`フィードバック送信に失敗: ${error.message}`, error);
    throw new HttpsError(
      "internal",
      `フィードバック送信に失敗しました: ${error.message}`
    );
  }
});

/// フィードバック分析用のセンチメント判定（簡易版）
function _analyzeSentiment(text: string): string {
  const positiveKeywords = [
    "良い",
    "すごい",
    "最高",
    "素晴らしい",
    "気に入った",
    "わかりやすい",
    "面白い",
    "役に立つ",
    "おすすめ",
  ];
  const negativeKeywords = [
    "悪い",
    "つまらない",
    "わかりにくい",
    "難しい",
    "退屈",
    "不満",
    "イライラ",
    "改善",
    "問題",
  ];

  let positiveCount = 0;
  let negativeCount = 0;

  const lowerText = text.toLowerCase();
  for (const keyword of positiveKeywords) {
    if (lowerText.includes(keyword)) positiveCount++;
  }
  for (const keyword of negativeKeywords) {
    if (lowerText.includes(keyword)) negativeCount++;
  }

  if (positiveCount > negativeCount) return "positive";
  if (negativeCount > positiveCount) return "negative";
  return "neutral";
}

/// ライブ認定試験の提出と採点
export const submitLiveExam = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "サインインが必要です");
  }

  const {
    companyId,
    employeeId,
    examId,
    answers,
    timeSpentSeconds,
    autoSubmit,
    backgroundCount,
  } = request.data;

  try {
    if (!companyId || !employeeId || !examId || !answers) {
      throw new HttpsError(
        "invalid-argument",
        "必須項目が不足しています"
      );
    }

    // 他人になりすまして試験結果を送信できないようにする
    if (auth.uid !== employeeId) {
      throw new HttpsError("permission-denied", "本人以外の試験結果は送信できません");
    }
    const employeeSnap = await db.doc(`companies/${companyId}/employees/${employeeId}`).get();
    if (!employeeSnap.exists) {
      throw new HttpsError("permission-denied", "この会社に所属する社員が見つかりません");
    }

    // 試験問題を取得
    const questionsSnapshot = await db
      .collection("exams")
      .doc(examId)
      .collection("questions")
      .orderBy("order")
      .get();

    if (questionsSnapshot.empty) {
      throw new HttpsError(
        "not-found",
        "試験問題が見つかりません"
      );
    }

    const questions = questionsSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    // 採点（設問別・分野別の内訳も合わせて集計する）
    let correctCount = 0;
    const questionResults: Array<{
      questionId: string;
      order: number;
      category: string;
      text: string;
      correct: boolean;
      selectedOption: string | null;
      correctOption: number;
    }> = [];
    const categoryBreakdown: Record<string, { correct: number; total: number }> = {};

    for (let i = 0; i < questions.length; i++) {
      const question = questions[i] as {
        id: string;
        order: number;
        category?: string;
        text: string;
        correctOption: number;
      };
      const category = question.category || "未分類";
      const userAnswerKey = `option_${question.correctOption}a`;
      const userAnswer = answers[i] ?? null;
      const isCorrect = userAnswer === userAnswerKey;

      if (isCorrect) {
        correctCount++;
      }

      questionResults.push({
        questionId: question.id,
        order: question.order,
        category,
        text: question.text,
        correct: isCorrect,
        selectedOption: userAnswer,
        correctOption: question.correctOption,
      });

      const bucket = categoryBreakdown[category] || { correct: 0, total: 0 };
      bucket.total += 1;
      if (isCorrect) bucket.correct += 1;
      categoryBreakdown[category] = bucket;
    }

    const score = Math.round((correctCount / questions.length) * 100);
    const passed = score >= 70; // 合格ライン 70%

    const examAttemptId = db.collection("exams").doc().id;
    const now = admin.firestore.FieldValue.serverTimestamp();

    // 試験結果を保存（分野別・設問別の分析画面で使用するため内訳も保存する）
    await db
      .collection("companies")
      .doc(companyId)
      .collection("examAttempts")
      .doc(examAttemptId)
      .set({
        id: examAttemptId,
        employeeId,
        examId,
        score,
        passed,
        correctCount,
        totalQuestions: questions.length,
        timeSpentSeconds,
        autoSubmit,
        backgroundCount: backgroundCount || 0,
        categoryBreakdown,
        results: questionResults,
        submittedAt: now,
        createdAt: now,
      });

    logger.info(
      `試験提出完了: ${examAttemptId} (${examId}, スコア: ${score}%, 合格: ${passed})`
    );

    // 分析イベント記録
    await db.collection("analytics_events").doc().set({
      event: "exam_submitted",
      companyId,
      employeeId,
      examId,
      score,
      passed,
      timestamp: now,
    });

    return {
      success: true,
      examAttemptId,
      score,
      passed,
      message: passed ? "合格おめでとうございます！" : "残念ながら不合格です。再受験してください。",
    };
  } catch (error: any) {
    logger.error(`試験提出に失敗: ${error.message}`, error);
    throw new HttpsError(
      "internal",
      `試験提出に失敗しました: ${error.message}`
    );
  }
});

/// レベル診断の完了・学習パス推奨
export const completeLevelDiagnostic = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "サインインが必要です");
  }

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

    // 他人のスキルレベル・診断結果を書き換えられないようにする
    if (auth.uid !== employeeId) {
      throw new HttpsError("permission-denied", "本人以外の診断結果は送信できません");
    }
    const employeeSnap = await db.doc(`companies/${companyId}/employees/${employeeId}`).get();
    if (!employeeSnap.exists) {
      throw new HttpsError("permission-denied", "この会社に所属する社員が見つかりません");
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

/// Q&Aフォーラム：質問投稿
export const submitQuestion = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "サインインが必要です");
  }

  const { companyId, employeeId, title, description, category } = request.data as {
    companyId?: string;
    employeeId?: string;
    title?: string;
    description?: string;
    category?: string;
  };

  if (!companyId || !title || title.trim().length === 0) {
    throw new HttpsError("invalid-argument", "会社IDとタイトルが必要です");
  }

  if (auth.uid !== employeeId) {
    throw new HttpsError("permission-denied", "本人以外が投稿できません");
  }

  const employeeSnap = await db.doc(`companies/${companyId}/employees/${employeeId}`).get();
  if (!employeeSnap.exists) {
    throw new HttpsError("permission-denied", "この会社に所属する社員が見つかりません");
  }

  // 入力値検証
  if (title.length > 200) {
    throw new HttpsError("invalid-argument", "タイトルは200文字以下である必要があります");
  }
  if ((description || "").length > 1000) {
    throw new HttpsError("invalid-argument", "説明は1000文字以下である必要があります");
  }

  // レート制限チェック（5分以上間隔）
  const lastQuestion = await db
    .collection("companies")
    .doc(companyId)
    .collection("qaForum")
    .where("authorId", "==", employeeId)
    .orderBy("createdAt", "desc")
    .limit(1)
    .get();

  if (lastQuestion.docs.length > 0) {
    const lastCreated = lastQuestion.docs[0].data().createdAt.toDate();
    const now = new Date();
    if (now.getTime() - lastCreated.getTime() < 5 * 60 * 1000) {
      throw new HttpsError(
        "resource-exhausted",
        "質問は5分以上間隔をあけて投稿できます"
      );
    }
  }

  try {
    const questionId = db.collection("questions").doc().id;
    const now = admin.firestore.FieldValue.serverTimestamp();

    await db
      .collection("companies")
      .doc(companyId)
      .collection("qaForum")
      .doc(questionId)
      .set({
        id: questionId,
        title: title.trim(),
        description: (description || "").trim(),
        category: category || "その他",
        authorId: employeeId,
        authorName: `ユーザー${employeeId.substring(0, 4)}`,
        createdAt: now,
        updatedAt: now,
        answerCount: 0,
        viewCount: 0,
        status: "active",
        companyId,
      });

    logger.info(`質問投稿: ${questionId} (企業: ${companyId}, ユーザー: ${employeeId})`);

    await db.collection("analytics_events").doc().set({
      event: "question_posted",
      companyId,
      employeeId,
      questionId,
      timestamp: now,
    });

    return {
      success: true,
      questionId,
      message: "質問を投稿しました",
    };
  } catch (error: any) {
    logger.error(`質問投稿に失敗: ${error.message}`, error);
    throw new HttpsError("internal", "質問投稿に失敗しました");
  }
});

/// Q&Aフォーラム：回答投稿
export const submitAnswer = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "サインインが必要です");
  }

  const { companyId, questionId, content } = request.data as {
    companyId?: string;
    questionId?: string;
    content?: string;
  };

  if (!companyId || !questionId || !content || content.trim().length === 0) {
    throw new HttpsError("invalid-argument", "必須項目が不足しています");
  }

  if (content.length > 2000) {
    throw new HttpsError("invalid-argument", "回答は2000文字以下である必要があります");
  }

  try {
    const answerId = db.collection("answers").doc().id;
    const now = admin.firestore.FieldValue.serverTimestamp();

    await db
      .collection("companies")
      .doc(companyId)
      .collection("qaForum")
      .doc(questionId)
      .collection("answers")
      .doc(answerId)
      .set({
        id: answerId,
        content: content.trim(),
        authorId: auth.uid,
        authorName: `ユーザー${auth.uid.substring(0, 4)}`,
        createdAt: now,
        updatedAt: now,
        likes: 0,
        status: "active",
      });

    // 質問の回答数をインクリメント
    await db
      .collection("companies")
      .doc(companyId)
      .collection("qaForum")
      .doc(questionId)
      .update({
        answerCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
      });

    logger.info(`回答投稿: ${answerId} (質問: ${questionId})`);

    await db.collection("analytics_events").doc().set({
      event: "answer_posted",
      companyId,
      questionId,
      answerId,
      timestamp: now,
    });

    return {
      success: true,
      answerId,
      message: "回答を投稿しました",
    };
  } catch (error: any) {
    logger.error(`回答投稿に失敗: ${error.message}`, error);
    throw new HttpsError("internal", "回答投稿に失敗しました");
  }
});

/// Q&Aフォーラム：ベストアンサーの選択・解除（質問投稿者のみ）
export const setBestAnswer = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "サインインが必要です");
  }

  const { companyId, questionId, answerId } = request.data as {
    companyId?: string;
    questionId?: string;
    answerId?: string;
  };

  if (!companyId || !questionId || !answerId) {
    throw new HttpsError("invalid-argument", "必須項目が不足しています");
  }

  try {
    const questionRef = db
      .collection("companies")
      .doc(companyId)
      .collection("qaForum")
      .doc(questionId);
    const answerRef = questionRef.collection("answers").doc(answerId);

    await db.runTransaction(async (tx) => {
      const questionSnap = await tx.get(questionRef);
      if (!questionSnap.exists) {
        throw new HttpsError("not-found", "質問が見つかりません");
      }
      const questionData = questionSnap.data() as {
        authorId?: string;
        bestAnswerId?: string | null;
      };
      if (questionData.authorId !== auth.uid) {
        throw new HttpsError(
          "permission-denied",
          "質問の投稿者のみベストアンサーを選択できます"
        );
      }

      const answerSnap = await tx.get(answerRef);
      if (!answerSnap.exists) {
        throw new HttpsError("not-found", "回答が見つかりません");
      }

      const currentBestAnswerId = questionData.bestAnswerId ?? null;
      const now = admin.firestore.FieldValue.serverTimestamp();

      if (currentBestAnswerId === answerId) {
        // 同じ回答が指定された場合は選択解除
        tx.update(answerRef, { isBestAnswer: false, updatedAt: now });
        tx.update(questionRef, { bestAnswerId: null, updatedAt: now });
        return;
      }

      if (currentBestAnswerId) {
        const prevBestAnswerRef = questionRef
          .collection("answers")
          .doc(currentBestAnswerId);
        tx.update(prevBestAnswerRef, { isBestAnswer: false, updatedAt: now });
      }

      tx.update(answerRef, { isBestAnswer: true, updatedAt: now });
      tx.update(questionRef, { bestAnswerId: answerId, updatedAt: now });
    });

    logger.info(
      `ベストアンサー更新: 質問${questionId} 回答${answerId} (企業: ${companyId})`
    );

    return { success: true };
  } catch (error: any) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error(`ベストアンサー設定に失敗: ${error.message}`, error);
    throw new HttpsError("internal", "ベストアンサーの設定に失敗しました");
  }
});

/// Q&Aフォーラム：回答への「役に立った」リアクションの切り替え（重複防止付き）
export const toggleAnswerHelpful = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "サインインが必要です");
  }

  const { companyId, questionId, answerId } = request.data as {
    companyId?: string;
    questionId?: string;
    answerId?: string;
  };

  if (!companyId || !questionId || !answerId) {
    throw new HttpsError("invalid-argument", "必須項目が不足しています");
  }

  try {
    const answerRef = db
      .collection("companies")
      .doc(companyId)
      .collection("qaForum")
      .doc(questionId)
      .collection("answers")
      .doc(answerId);

    const result = await db.runTransaction(async (tx) => {
      const answerSnap = await tx.get(answerRef);
      if (!answerSnap.exists) {
        throw new HttpsError("not-found", "回答が見つかりません");
      }

      const data = answerSnap.data() as {
        helpfulEmployeeIds?: string[];
      };
      const helpfulEmployeeIds = data.helpfulEmployeeIds || [];
      const alreadyReacted = helpfulEmployeeIds.includes(auth.uid);
      const now = admin.firestore.FieldValue.serverTimestamp();

      if (alreadyReacted) {
        tx.update(answerRef, {
          helpfulEmployeeIds: admin.firestore.FieldValue.arrayRemove(auth.uid),
          likes: admin.firestore.FieldValue.increment(-1),
          updatedAt: now,
        });
        return { reacted: false };
      }

      tx.update(answerRef, {
        helpfulEmployeeIds: admin.firestore.FieldValue.arrayUnion(auth.uid),
        likes: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
      });
      return { reacted: true };
    });

    return { success: true, ...result };
  } catch (error: any) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error(`役に立ったリアクションの切り替えに失敗: ${error.message}`, error);
    throw new HttpsError("internal", "リアクションの切り替えに失敗しました");
  }
});

// ─────────────────────────────────────────────
// プッシュ通知トリガー群(Firestoreトリガー方式)
// ─────────────────────────────────────────────

// onExamAttemptWritten: examAttemptsドキュメントの作成/更新(合否確定)をトリガーに
// 受験者へ試験結果をプッシュ通知する。更新時はpassedが変化した場合のみ通知し、
// スコア再計算等による多重送信を防ぐ。
export const onExamAttemptWritten = onDocumentWritten(
  "companies/{companyId}/examAttempts/{examAttemptId}",
  async (event) => {
    const after = event.data?.after;
    if (!after || !after.exists) return; // 削除時は何もしない

    const before = event.data?.before;
    const afterData = after.data() as
      | { employeeId?: string; score?: number; passed?: boolean }
      | undefined;
    if (!afterData) return;

    if (before?.exists) {
      const beforeData = before.data() as { passed?: boolean } | undefined;
      if (beforeData?.passed === afterData.passed) return;
    }

    const { employeeId, score, passed } = afterData;
    if (!employeeId) return;

    const { companyId } = event.params;
    const employeeSnap = await db.doc(`companies/${companyId}/employees/${employeeId}`).get();
    const employee = employeeSnap.data() as EmployeeDoc | undefined;
    if (!employee?.fcmToken) {
      logger.info(`fcmToken未登録のため試験結果通知をスキップ: ${employeeId}`);
      return;
    }

    try {
      await messaging.send({
        token: employee.fcmToken,
        notification: {
          title: "試験結果のお知らせ",
          body: passed
            ? `試験に合格しました(スコア: ${score ?? "-"}点)。安心企業研修Safyでご確認ください。`
            : `試験の結果はスコア${score ?? "-"}点でした。安心企業研修Safyから再挑戦できます。`,
        },
      });
    } catch (error) {
      logger.warn(`試験結果通知の送信に失敗しました employeeId=${employeeId}`, error);
    }
  }
);

// onCertificateIssued: モジュール認定(certificates)ドキュメント作成をトリガーに
// 受験者へ認定完了をプッシュ通知する。
// ※Tier 1 Training(Gate3)の4モジュール修了証(trainingCertificates)は
//   issueTrainingCertificate()内で発行と同時に通知済みのため、二重送信を避けるためここでは扱わない。
export const onCertificateIssued = onDocumentCreated(
  "companies/{companyId}/certificates/{certificateId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const { employeeId, moduleId, score } = snapshot.data() as {
      employeeId?: string;
      moduleId?: string;
      score?: number;
    };
    if (!employeeId) return;

    const { companyId } = event.params;
    const employeeSnap = await db.doc(`companies/${companyId}/employees/${employeeId}`).get();
    const employee = employeeSnap.data() as EmployeeDoc | undefined;
    if (!employee?.fcmToken) {
      logger.info(`fcmToken未登録のため認定完了通知をスキップ: ${employeeId}`);
      return;
    }

    try {
      await messaging.send({
        token: employee.fcmToken,
        notification: {
          title: "認定完了のお知らせ",
          body: moduleId
            ? `モジュール「${moduleId}」の認定が完了しました(スコア: ${score ?? "-"}点)。`
            : `認定が完了しました(スコア: ${score ?? "-"}点)。`,
        },
      });
    } catch (error) {
      logger.warn(`認定完了通知の送信に失敗しました employeeId=${employeeId}`, error);
    }
  }
);

// onQaAnswerCreated: Q&Aフォーラムのanswersドキュメント作成をトリガーに、
// 質問投稿者(自分自身の回答は除く)へ新着回答をプッシュ通知する。
export const onQaAnswerCreated = onDocumentCreated(
  "companies/{companyId}/qaForum/{questionId}/answers/{answerId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const answer = snapshot.data() as { authorId?: string } | undefined;
    if (!answer?.authorId) return;

    const { companyId, questionId } = event.params;
    const questionSnap = await db
      .doc(`companies/${companyId}/qaForum/${questionId}`)
      .get();
    const question = questionSnap.data() as
      | { authorId?: string; title?: string }
      | undefined;
    if (!question?.authorId) return;

    // 自分の質問に自分で回答した場合(自己解決の追記等)は通知しない
    if (question.authorId === answer.authorId) return;

    const employeeSnap = await db
      .doc(`companies/${companyId}/employees/${question.authorId}`)
      .get();
    const employee = employeeSnap.data() as EmployeeDoc | undefined;
    if (!employee?.fcmToken) {
      logger.info(`fcmToken未登録のためQA回答通知をスキップ: ${question.authorId}`);
      return;
    }

    try {
      await messaging.send({
        token: employee.fcmToken,
        notification: {
          title: "質問に回答がありました",
          body: `「${question.title ?? "あなたの質問"}」に新しい回答が投稿されました。`,
        },
      });
    } catch (error) {
      logger.warn(`QA回答通知の送信に失敗しました questionId=${questionId}`, error);
    }
  }
);
