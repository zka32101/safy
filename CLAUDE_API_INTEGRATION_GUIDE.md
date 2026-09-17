# Claude API 統合ガイド

**対象**: Cloud Functions での Claude API 実装  
**言語**: TypeScript  
**バージョン**: Phase 2c Stage 1  
**作成日**: 2026-09-17

---

## 目次

1. [環境セットアップ](#環境セットアップ)
2. [Claude API キー管理](#claude-api-キー管理)
3. [Cloud Functions 実装](#cloud-functions-実装)
4. [レート制限実装](#レート制限実装)
5. [エラーハンドリング](#エラーハンドリング)
6. [トークン管理・コスト最適化](#トークン管理コスト最適化)
7. [モニタリング・ログ](#モニタリング・ログ)

---

## 環境セットアップ

### 1. 依存パッケージ

```bash
cd functions
npm install @anthropic-ai/sdk
npm install redis
npm install dotenv
npm install firebase-admin
npm install firebase-functions
```

### 2. 環境変数設定

```bash
# .env.local (ローカル開発)
CLAUDE_API_KEY=sk-ant-v7-...
REDIS_HOST=localhost
REDIS_PORT=6379
FIRESTORE_PROJECT_ID=safy-prod

# Firebase Secret Manager (本番)
gcloud secrets create claude-api-key \
  --replication-policy="automatic" \
  --data-file=- <<< "sk-ant-v7-..."
```

### 3. Firebase 設定

```typescript
// functions/src/config.ts
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

admin.initializeApp();

export const db = admin.firestore();
export const auth = admin.auth();

// Secret Manager からキーを取得
const secretManager = new secretsV1.SecretManagerServiceClient();

export async function getClaudeApiKey(): Promise<string> {
  const projectId = process.env.GCP_PROJECT || 'safy-prod';
  const secretName = `projects/${projectId}/secrets/claude-api-key/versions/latest`;
  
  try {
    const [version] = await secretManager.accessSecretVersion({ name: secretName });
    const payload = version.payload?.data as string;
    return Buffer.from(payload, 'base64').toString('utf8');
  } catch (error) {
    functions.logger.error('Failed to get Claude API key:', error);
    throw new Error('Claude API キーの取得に失敗しました');
  }
}
```

---

## Claude API キー管理

### ベストプラクティス

```typescript
// functions/src/services/claude-service.ts
import Anthropic from '@anthropic-ai/sdk';
import * as functions from 'firebase-functions';

class ClaudeService {
  private client: Anthropic;
  private apiKey: string;

  constructor(apiKey: string) {
    this.apiKey = apiKey;
    this.client = new Anthropic({ apiKey });
  }

  // API キーは環境変数・Secret Manager から取得
  static async initialize(): Promise<ClaudeService> {
    const apiKey = process.env.CLAUDE_API_KEY || 
      await getClaudeApiKey(); // Secret Manager から取得
    
    if (!apiKey) {
      throw new Error('Claude API キーが設定されていません');
    }

    return new ClaudeService(apiKey);
  }

  // キーのローテーション (3ヶ月ごと)
  async validateAndRefresh(): Promise<void> {
    try {
      // テスト API コール実行
      await this.client.messages.create({
        model: 'claude-3-5-sonnet-20241022',
        max_tokens: 1,
        messages: [{ role: 'user', content: 'test' }]
      });
      functions.logger.info('Claude API キー検証成功');
    } catch (error) {
      functions.logger.error('Claude API キー検証失敗:', error);
      throw error;
    }
  }
}

export default ClaudeService;
```

### キーのセキュリティチェック

```typescript
// キーが GitHub などにコミットされていないか確認
function validateNoSecrets(code: string): boolean {
  const secretPatterns = [
    /sk-ant-[a-zA-Z0-9]{20,}/g, // Claude API キー
    /AIzaSy[a-zA-Z0-9-_]{33}/g, // Google API キー
    /AKIA[0-9A-Z]{16}/g         // AWS キー
  ];

  for (const pattern of secretPatterns) {
    if (pattern.test(code)) {
      return false;
    }
  }
  return true;
}
```

---

## Cloud Functions 実装

### Cloud Function: callAIChatbot

```typescript
// functions/src/index.ts
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import Anthropic from '@anthropic-ai/sdk';
import { validateChatRequest } from './validators/chat-validator';
import { checkRateLimit } from './services/rate-limiter';
import { trackUsage } from './services/usage-tracker';
import { generateSystemPrompt } from './services/prompt-service';

const db = admin.firestore();

interface ChatRequest {
  companyId: string;
  employeeId: string;
  moduleId?: string;
  message: string;
  conversationId?: string;
}

interface ChatResponse {
  conversationId: string;
  message: string;
  tokenCount: number;
  cost: number;
  timestamp: Date;
}

export const callAIChatbot = functions
  .region('asia-northeast1')
  .https.onCall(async (data: ChatRequest, context) => {
    const startTime = Date.now();

    try {
      // 1. 認証チェック
      if (!context.auth) {
        throw new functions.https.HttpsError(
          'unauthenticated',
          '認証が必要です'
        );
      }

      const userId = context.auth.uid;
      const { companyId, employeeId, moduleId, message, conversationId } = data;

      // 2. リクエスト検証
      const validation = validateChatRequest(data);
      if (!validation.valid) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `検証エラー: ${validation.errors.join(', ')}`
        );
      }

      // 3. Company メンバーシップ確認
      const isMember = await checkCompanyMembership(userId, companyId);
      if (!isMember) {
        throw new functions.https.HttpsError(
          'permission-denied',
          '権限がありません'
        );
      }

      // 4. レート制限チェック
      const rateLimitOK = await checkRateLimit(userId, companyId);
      if (!rateLimitOK) {
        throw new functions.https.HttpsError(
          'resource-exhausted',
          '質問が多すぎます。しばらく待ってから再度お試しください'
        );
      }

      // 5. コンテキスト準備
      const employeeData = await getEmployeeData(companyId, employeeId);
      const conversationHistory = conversationId 
        ? await getConversationHistory(companyId, conversationId)
        : [];

      // 6. System Prompt 生成
      const systemPrompt = generateSystemPrompt({
        employeeLevel: employeeData.level,
        moduleId: moduleId || 'general',
        careerGoal: employeeData.careerGoal,
        learningHistory: conversationHistory
      });

      // 7. Claude API コール
      const client = new Anthropic({
        apiKey: process.env.CLAUDE_API_KEY || await getClaudeApiKey()
      });

      const response = await client.messages.create({
        model: 'claude-3-5-sonnet-20241022',
        max_tokens: 1024,
        system: systemPrompt,
        messages: [
          ...conversationHistory.map(msg => ({
            role: msg.role as 'user' | 'assistant',
            content: msg.content
          })),
          {
            role: 'user' as const,
            content: message
          }
        ]
      });

      // 8. レスポンス処理
      const assistantMessage = response.content[0];
      if (assistantMessage.type !== 'text') {
        throw new Error('予期しないレスポンス形式');
      }

      const inputTokens = response.usage.input_tokens;
      const outputTokens = response.usage.output_tokens;
      const totalTokens = inputTokens + outputTokens;

      // コスト計算
      const inputCost = (inputTokens / 1000000) * 3;     // $3/1M input
      const outputCost = (outputTokens / 1000000) * 15;  // $15/1M output
      const totalCost = inputCost + outputCost;

      // 9. Firestore に保存
      const finalConversationId = conversationId || generateConversationId();
      const convRef = db.collection('companies')
        .doc(companyId)
        .collection('aiConversations')
        .doc(finalConversationId);

      await convRef.update({
        messages: admin.firestore.FieldValue.arrayUnion(
          {
            role: 'user',
            content: message,
            timestamp: admin.firestore.Timestamp.now(),
            tokenCount: inputTokens
          },
          {
            role: 'assistant',
            content: assistantMessage.text,
            timestamp: admin.firestore.Timestamp.now(),
            tokenCount: outputTokens
          }
        ),
        totalTokens: admin.firestore.FieldValue.increment(totalTokens),
        totalCost: admin.firestore.FieldValue.increment(totalCost),
        updatedAt: admin.firestore.Timestamp.now()
      }).catch(async (error) => {
        // ドキュメントが存在しない場合は新規作成
        if (error.code === 'not-found') {
          await convRef.set({
            employeeId,
            createdAt: admin.firestore.Timestamp.now(),
            updatedAt: admin.firestore.Timestamp.now(),
            topic: `${moduleId || 'General'} - Chat`,
            context: {
              moduleId: moduleId || 'general',
              employeeLevel: employeeData.level,
              careerGoal: employeeData.careerGoal,
              lastDiagnosticScore: employeeData.diagnosticScore || 0
            },
            messages: [
              {
                role: 'user',
                content: message,
                timestamp: admin.firestore.Timestamp.now(),
                tokenCount: inputTokens,
                sentiment: analyzeSentiment(message)
              },
              {
                role: 'assistant',
                content: assistantMessage.text,
                timestamp: admin.firestore.Timestamp.now(),
                tokenCount: outputTokens,
                sourceModule: moduleId || 'general',
                usedTemplate: false
              }
            ],
            totalTokens,
            totalCost,
            feedback: {
              rating: 0,
              helpful: false,
              comment: '',
              timestamp: null
            },
            status: 'active'
          });
        } else {
          throw error;
        }
      });

      // 10. 使用統計を記録
      await trackUsage(companyId, {
        conversationId: finalConversationId,
        inputTokens,
        outputTokens,
        totalTokens,
        cost: totalCost,
        responseTime: Date.now() - startTime
      });

      // 11. レスポンス返却
      return {
        conversationId: finalConversationId,
        message: assistantMessage.text,
        tokenCount: totalTokens,
        cost: totalCost,
        timestamp: new Date().toISOString(),
        responseTime: Date.now() - startTime
      };
    } catch (error) {
      functions.logger.error('Claude API エラー:', error);

      if (error instanceof functions.https.HttpsError) {
        throw error;
      }

      throw new functions.https.HttpsError(
        'internal',
        '内部エラーが発生しました'
      );
    }
  });
```

---

## レート制限実装

### Redis を使用したレート制限

```typescript
// functions/src/services/rate-limiter.ts
import * as redis from 'redis';
import * as functions from 'firebase-functions';

const redisClient = redis.createClient({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379')
});

const RATE_LIMITS = {
  USER: {
    perMinute: 5,
    perHour: 30,
    perDay: 100
  },
  COMPANY: {
    perMinute: 50,
    perHour: 500,
    perMonth: 10000
  },
  COST: {
    dailyBudget: 20,
    monthlyBudget: 500
  }
};

async function checkRateLimit(userId: string, companyId: string): Promise<boolean> {
  const now = Date.now();
  const minute = Math.floor(now / 60000);
  const hour = Math.floor(now / 3600000);
  const day = Math.floor(now / 86400000);
  const month = Math.floor(now / 2592000000);

  // ユーザーベース制限
  const userMinuteKey = `rate:user:${userId}:min:${minute}`;
  const userHourKey = `rate:user:${userId}:hour:${hour}`;
  const userDayKey = `rate:user:${userId}:day:${day}`;

  const userMinuteCount = parseInt(await redisClient.get(userMinuteKey) || '0');
  const userHourCount = parseInt(await redisClient.get(userHourKey) || '0');
  const userDayCount = parseInt(await redisClient.get(userDayKey) || '0');

  if (userMinuteCount >= RATE_LIMITS.USER.perMinute ||
      userHourCount >= RATE_LIMITS.USER.perHour ||
      userDayCount >= RATE_LIMITS.USER.perDay) {
    functions.logger.warn(`ユーザー ${userId} がレート制限に達しました`);
    return false;
  }

  // Company ベース制限
  const companyMinuteKey = `rate:company:${companyId}:min:${minute}`;
  const companyHourKey = `rate:company:${companyId}:hour:${hour}`;
  const companyMonthKey = `rate:company:${companyId}:month:${month}`;

  const companyMinuteCount = parseInt(await redisClient.get(companyMinuteKey) || '0');
  const companyHourCount = parseInt(await redisClient.get(companyHourKey) || '0');
  const companyMonthCount = parseInt(await redisClient.get(companyMonthKey) || '0');

  if (companyMinuteCount >= RATE_LIMITS.COMPANY.perMinute ||
      companyHourCount >= RATE_LIMITS.COMPANY.perHour ||
      companyMonthCount >= RATE_LIMITS.COMPANY.perMonth) {
    functions.logger.warn(`Company ${companyId} がレート制限に達しました`);
    return false;
  }

  // 制限に引っかからなければカウントをインクリメント
  await Promise.all([
    redisClient.incr(userMinuteKey),
    redisClient.incr(userHourKey),
    redisClient.incr(userDayKey),
    redisClient.incr(companyMinuteKey),
    redisClient.incr(companyHourKey),
    redisClient.incr(companyMonthKey)
  ]);

  // 期限設定
  await Promise.all([
    redisClient.expire(userMinuteKey, 60),
    redisClient.expire(userHourKey, 3600),
    redisClient.expire(userDayKey, 86400),
    redisClient.expire(companyMinuteKey, 60),
    redisClient.expire(companyHourKey, 3600),
    redisClient.expire(companyMonthKey, 2592000)
  ]);

  return true;
}

export { checkRateLimit };
```

---

## エラーハンドリング

### ユーザーフレンドリーなエラーメッセージ

```typescript
// functions/src/utils/error-handler.ts
import * as functions from 'firebase-functions';

interface ErrorResponse {
  code: string;
  userMessage: string;
  logDetails: string;
  recoveryAction?: string;
}

const ERROR_MESSAGES: { [key: string]: ErrorResponse } = {
  INVALID_INPUT: {
    code: '400',
    userMessage: '質問の形式が正しくありません。別の表現でお試しください。',
    logDetails: 'Request validation failed'
  },
  RATE_LIMITED: {
    code: '429',
    userMessage: '質問が多すぎます。しばらく待ってから再度お試しください。',
    logDetails: 'Rate limit exceeded'
  },
  AUTH_FAILED: {
    code: '401',
    userMessage: '認証が失敗しました。もう一度ログインしてください。',
    logDetails: 'Authentication failed'
  },
  PERMISSION_DENIED: {
    code: '403',
    userMessage: '権限がありません。管理者にお問い合わせください。',
    logDetails: 'Permission denied'
  },
  API_ERROR: {
    code: '500',
    userMessage: '一時的なエラーが発生しました。後ほどお試しください。',
    logDetails: 'Claude API error'
  },
  INTERNAL_ERROR: {
    code: '500',
    userMessage: 'システムエラーが発生しました。サポートにお問い合わせください。',
    logDetails: 'Internal server error'
  }
};

function handleError(errorType: string, context: any = {}): void {
  const error = ERROR_MESSAGES[errorType];
  
  // ユーザーには安全なメッセージを表示
  functions.logger.info(`ユーザーメッセージ: ${error.userMessage}`);
  
  // ログには詳細情報を記録
  functions.logger.error(`エラーコード: ${error.code}`, {
    errorType,
    logDetails: error.logDetails,
    context,
    timestamp: new Date().toISOString()
  });
}

export { handleError, ERROR_MESSAGES };
```

---

## トークン管理・コスト最適化

### トークン数の推定と最適化

```typescript
// functions/src/utils/token-counter.ts
function estimateTokenCount(text: string): number {
  // 簡易推定: 日本語は約 0.5-1 文字 = 1 トークン
  // 英語は約 4 文字 = 1 トークン
  const japaneseCount = (text.match(/[぀-ゟ゠-ヿ一-鿿]/g) || []).length;
  const englishCount = text.replace(/[぀-ゟ゠-ヿ一-鿿]/g, '').length;
  
  return Math.ceil(japaneseCount / 1 + englishCount / 4);
}

function optimizePrompt(prompt: string, maxTokens: number = 1000): string {
  // 長すぎるプロンプトを短縮
  const tokens = estimateTokenCount(prompt);
  
  if (tokens <= maxTokens) {
    return prompt;
  }

  // 優先度順に削除
  let optimized = prompt;
  
  // 1. 長い例を削除
  optimized = optimized.replace(/例：[^。]*。/g, '');
  
  // 2. 注釈を削除
  optimized = optimized.replace(/（[^）]*）/g, '');
  
  // 3. 説明文を短縮
  optimized = optimized.replace(/してください。/g, '。');

  return optimized;
}

function calculateCost(inputTokens: number, outputTokens: number): number {
  const inputCost = (inputTokens / 1000000) * 3;     // $3/1M
  const outputCost = (outputTokens / 1000000) * 15;  // $15/1M
  return inputCost + outputCost;
}

export { estimateTokenCount, optimizePrompt, calculateCost };
```

---

## モニタリング・ログ

### Cloud Logging と Cloud Trace

```typescript
// functions/src/services/monitoring.ts
import * as functions from 'firebase-functions';
import { CloudTrace } from '@google-cloud/trace-agent';

interface MetricsData {
  conversationId: string;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  cost: number;
  responseTime: number;
  timestamp: Date;
  success: boolean;
  errorMessage?: string;
}

async function logMetrics(companyId: string, metrics: MetricsData): Promise<void> {
  // Cloud Logging への記録
  functions.logger.info('AI チャットボット使用統計', {
    companyId,
    conversationId: metrics.conversationId,
    inputTokens: metrics.inputTokens,
    outputTokens: metrics.outputTokens,
    totalTokens: metrics.totalTokens,
    cost: metrics.cost,
    responseTime: metrics.responseTime,
    timestamp: metrics.timestamp.toISOString(),
    success: metrics.success
  });

  // Firestore の aiUsageMetrics に記録
  const date = new Date(metrics.timestamp);
  const dateStr = date.toISOString().split('T')[0];
  
  const metricsRef = db.collection('companies')
    .doc(companyId)
    .collection('aiUsageMetrics')
    .doc(dateStr);

  await metricsRef.update({
    totalConversations: admin.firestore.FieldValue.increment(1),
    totalMessages: admin.firestore.FieldValue.increment(2), // user + assistant
    totalTokens: admin.firestore.FieldValue.increment(metrics.totalTokens),
    totalCost: admin.firestore.FieldValue.increment(metrics.cost),
    averageResponseTime: admin.firestore.FieldValue.increment(metrics.responseTime)
  }).catch(async (error) => {
    if (error.code === 'not-found') {
      await metricsRef.set({
        date: admin.firestore.Timestamp.fromDate(date),
        totalConversations: 1,
        totalMessages: 2,
        totalTokens: metrics.totalTokens,
        totalCost: metrics.cost,
        averageResponseTime: metrics.responseTime,
        userSatisfaction: 0,
        topicsRequested: {},
        errorCount: metrics.success ? 0 : 1
      });
    } else {
      throw error;
    }
  });
}

export { logMetrics };
```

---

## デプロイメント

### Firebase Deploy

```bash
# デプロイ前にテスト
cd functions
npm run test

# 本番環境へデプロイ
firebase deploy --only functions:callAIChatbot

# 特定環境にデプロイ
firebase deploy --only functions:callAIChatbot --project safy-prod

# デプロイ状況確認
firebase functions:log --limit=50

# ロールバック
firebase functions:delete callAIChatbot
```

---

## トラブルシューティング

| 問題 | 原因 | 対策 |
|------|------|------|
| API キーエラー | キーの期限切れ・無効 | Secret Manager 確認・キー再生成 |
| タイムアウト | Claude API 応答遅延 | タイムアウト値増加・リトライロジック実装 |
| レート制限エラー | 使用量超過 | レート制限設定確認・制限削減 |
| Firestore エラー | コレクション/フィールド不存在 | スキーマ確認・マイグレーション実行 |
| メモリ不足 | 会話履歴が大きすぎる | 履歴サイズ制限・圧縮実装 |

---

**ステータス**: 📋 実装準備中  
**最終更新**: 2026-09-17  
**次版**: Phase 2c Stage 1 実装開始時（2026-09-24）
