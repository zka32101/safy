# Phase 2c Stage 1: Claude API チャットボット設計書

**作成日**: 2026-09-17  
**実装期間**: 2026-09-24 ~ 2026-10-22（4週間）  
**ステータス**: 📋 設計準備中

---

## 📌 概要

Safy プラットフォームに Claude API を統合した AI チューター機能を実装します。

従業員の個別質問に対し、リアルタイムで教育的・実践的な回答を提供するシステムです。

**目標**:
- ✅ 学習サポート自動化（人件費 40% 削減）
- ✅ 24/7 個別指導体験
- ✅ 学習効果 20% 向上

---

## 🤖 Claude API 選定理由

### 選定評価

| 項目 | Claude 3.5 | GPT-4o | Gemini Pro |
|-----|----------|--------|-----------|
| 教育コンテンツ生成 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| 日本語対応 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| コスト効率 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| レスポンス速度 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| セキュリティ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| 日本企業対応 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |

**選定**: Claude 3.5 Sonnet（最適バランス）

### モデル仕様

```
モデル: Claude 3.5 Sonnet
特性:
  - Context Window: 200,000 トークン
  - 日本語ネイティブ対応
  - 推論能力: 高（ビジネス文脈理解）
  - 実行速度: 約 2-3 秒/レスポンス
  - コスト: $3/1M入力トークン, $15/1M出力トークン

推定使用量:
  - ユーザー: 500人
  - 平均質問数: 5問/月/人
  - 平均入力: 200トークン
  - 平均出力: 300トークン
  - 月額コスト: 約 $150-200
```

---

## 🏗️ システムアーキテクチャ

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App                       │
│  ┌──────────────────────────────────────────────┐  │
│  │  AITutorScreen                               │  │
│  │  ├─ ChatMessageList (メッセージ表示)         │  │
│  │  ├─ ChatInputField (ユーザー入力)            │  │
│  │  ├─ ContextSidebar (学習背景・アンダー等)   │  │
│  │  └─ QuickActionsBar (テンプレート質問)      │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                         ↑
                    REST API / gRPC
                         ↓
┌─────────────────────────────────────────────────────┐
│              Cloud Functions                        │
│  ┌──────────────────────────────────────────────┐  │
│  │  callAIChatbot() - HTTPS Callable            │  │
│  │  ├─ Input Validation                        │  │
│  │  ├─ Context Management                      │  │
│  │  ├─ Rate Limiting Check                     │  │
│  │  ├─ Claude API Call                         │  │
│  │  ├─ Response Processing                     │  │
│  │  └─ Analytics Logging                       │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                         ↑
                    Claude API
                         ↓
┌─────────────────────────────────────────────────────┐
│           Firestore Database                        │
│  ┌──────────────────────────────────────────────┐  │
│  │  companies/{companyId}/                      │  │
│  │  ├─ aiConversations/{conversationId}        │  │
│  │  │  ├─ messages[] (履歴)                    │  │
│  │  │  ├─ context (背景情報)                   │  │
│  │  │  └─ metadata (メタデータ)                │  │
│  │  ├─ aiUsageMetrics/ (利用統計)             │  │
│  │  └─ aiFeedback/ (ユーザーフィードバック)  │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## 💬 UI/UX 設計

### AITutorScreen レイアウト

```
┌─────────────────────────────────────┐
│ AI チューター                        │ ← Header
├─────────────────────────────────────┤
│                                     │
│ Claude: こんにちは！何についてお  │
│ 手伝いしましょうか？              │
│                                     │
│ You: モジュール1のQ3がわかりません │
│                                     │
│ Claude: なるほど。そのテーマは...  │
│                                     │ ← ChatMessageList
│ You: なぜそうなるんですか？        │
│                                     │
│ Claude: 良い質問ですね。背景と... │
│                                     │
│                                     │ ← Scroll Area
├─────────────────────────────────────┤
│ 📋 背景: Module 1 Quiz 3           │ ← ContextSidebar
│ 📚 Level: Intermediate             │
│ ⏱️  Duration: 3m 45s              │
├─────────────────────────────────────┤
│ [よくある質問] [例を見る] [詳細]  │ ← QuickActionsBar
├─────────────────────────────────────┤
│ メッセージを入力...               │
│ [送信]                              │ ← ChatInputField
└─────────────────────────────────────┘
```

### チャットメッセージデザイン

```
User Message:
┌──────────────────────────────────┐
│ あなたの質問です                  │
│                        [You]     │
│                      10分前      │
└──────────────────────────────────┘

Claude Response:
┌──────────────────────────────────┐
│ [Claude AI]
│ 回答です。段落分け・マークダウン
│ - リスト1
│ - リスト2
│ 
│ コード例:
│ ```dart
│ code()
│ ```
│ 
│ 参考: Module 2, Lesson 3 を確認
│                      2分前      │
└──────────────────────────────────┘
```

---

## 🧠 Prompt エンジニアリング

### システム Prompt テンプレート

```
あなたは Safy という企業研修プラットフォームの AI チューターです。

【ロール】
- 中小企業従業員向けの教育コンサルタント
- ビジネススキル・デジタルリテラシー指導者
- 業務レベル診断エンジニア
- 専門用語は日本語で説明

【コンテキスト】
- ユーザーレベル: {LEVEL} (Beginner/Intermediate/Advanced)
- 学習モジュール: {MODULE}
- キャリアゴール: {CAREER_GOAL}
- 過去の学習履歴: {LEARNING_HISTORY}

【指導方針】
1. 実践的な例を必ず含める
2. ユーザーレベルに合わせた難易度調整
3. わかりやすく、簡潔に（100-200 語目安）
4. 業務での応用方法を示唆
5. わからない場合は正直に「わかりません」と答える

【禁止事項】
- 個人情報の保存
- 学習内容の外での雑談
- 長すぎる回答（500 字以上は避ける）
- 推測による回答

【出力フォーマット】
- 見出しは # マークダウン
- リスト項目は - で統一
- コード例は ``` で囲む
- 参考資料は明記

では、{USER_QUESTION} について説明します。
```

### Dynamic Context 管理

```typescript
// ユーザーレベルに応じた調整
const LEVEL_INSTRUCTIONS = {
  beginner: "基礎概念から丁寧に説明。難しい用語は避ける。",
  intermediate: "実務応用を意識した説明。業界標準に合わせる。",
  advanced: "理論的背景・最新トレンドに触れる。最適化案を提示。"
};

// モジュール別の背景知識
const MODULE_CONTEXT = {
  "Platform Tech": "クラウド・API・インフラ基礎",
  "Operations": "業務効率化・プロセス改善",
  "Content Production": "マーケティング・ブランディング",
  "GTM Strategy": "営業・市場戦略"
};

// 会話履歴による改善
const CONVERSATION_MEMORY = {
  maxMessages: 10,           // 直近 10 メッセージを維持
  summarizationThreshold: 20, // 20 メッセージでまとめる
  retentionDays: 30          // 30 日間保持
};
```

---

## 🔐 セキュリティ & レート制限

### 認証・認可

```typescript
// Cloud Functions エンドポイント
export async function callAIChatbot(
  request: Request,
  response: Response
) {
  // 1. Firebase Authentication チェック
  if (!request.auth) {
    return response.status(401).json({ error: '認証が必要です' });
  }

  // 2. Company メンバーシップ確認
  const userId = request.auth.uid;
  const companyId = request.body.companyId;
  
  const isMember = await checkCompanyMembership(userId, companyId);
  if (!isMember) {
    return response.status(403).json({ error: '権限がありません' });
  }

  // 3. リクエスト検証
  const validation = validateChatRequest(request.body);
  if (!validation.valid) {
    return response.status(400).json({ error: validation.errors });
  }
}
```

### レート制限戦略

```typescript
interface RateLimitConfig {
  // 1. ユーザーベース制限
  USER_LIMITS: {
    perMinute: 5,      // 1分間に最大 5 質問
    perHour: 30,       // 1時間に最大 30 質問
    perDay: 100        // 1日に最大 100 質問
  },

  // 2. Company ベース制限
  COMPANY_LIMITS: {
    perMinute: 50,     // 1分間に最大 50 質問
    perHour: 500,      // 1時間に最大 500 質問
    perMonth: 10000    // 1ヶ月に最大 10,000 質問
  },

  // 3. API コスト制限
  COST_LIMITS: {
    monthlyBudget: 500,        // 月額予算 $500
    dailyBudget: 20,           // 日額予算 $20
    perRequestMax: 0.50        // リクエストあたり最大 $0.50
  }
}

// Redis を使用したレート制限
const redis = new Redis();

async function checkRateLimit(userId: string): Promise<boolean> {
  const key = `rate-limit:${userId}:${getCurrentMinute()}`;
  const count = await redis.incr(key);
  
  if (count === 1) {
    await redis.expire(key, 60); // 60 秒で削除
  }
  
  return count <= LIMITS.USER_LIMITS.perMinute;
}
```

### エラーメッセージの安全性

```typescript
// エラー分類
const ERROR_HANDLING = {
  // ユーザーに表示する安全なメッセージ
  USER_SAFE: {
    rateLimited: "質問が多すぎます。しばらく待ってから再度お試しください。",
    apiError: "一時的なエラーが発生しました。後ほどお試しください。",
    invalidInput: "質問の形式が正しくありません。別の表現でお試しください。"
  },

  // ログに記録する詳細情報
  ADMIN_LOG: {
    timestamp: new Date(),
    userId: "***",
    error: "詳細なエラーメッセージ",
    stackTrace: "full stack trace",
    requestHash: "hash of request"
  }
};
```

---

## 📊 Firestore スキーマ

### aiConversations Collection

```firestore
companies/{companyId}/aiConversations/{conversationId}
├─ employeeId (string): "user123"
├─ createdAt (timestamp): 2026-09-24T10:30:00Z
├─ updatedAt (timestamp): 2026-09-24T10:35:00Z
├─ topic (string): "Module 1 - Platform Tech"
├─ context (map):
│  ├─ moduleId (string): "mod-001"
│  ├─ lessonId (string): "les-001"
│  ├─ quizId (string): "quiz-001"
│  ├─ employeeLevel (string): "intermediate"
│  ├─ careerGoal (string): "Engineering Manager"
│  └─ lastDiagnosticScore (number): 2.3
├─ messages (array of maps):
│  ├─ [0]:
│  │  ├─ role (string): "user"
│  │  ├─ content (string): "モジュール1のQ3がわかりません"
│  │  ├─ timestamp (timestamp): 2026-09-24T10:30:00Z
│  │  ├─ tokenCount (number): 28
│  │  └─ sentiment (string): "confused"
│  └─ [1]:
│     ├─ role (string): "assistant"
│     ├─ content (string): "そのテーマについて説明します..."
│     ├─ timestamp (timestamp): 2026-09-24T10:30:05Z
│     ├─ tokenCount (number): 156
│     ├─ sourceModule (string): "mod-001"
│     └─ usedTemplate (boolean): false
├─ totalTokens (number): 1234
├─ totalCost (number): 0.045
├─ feedback (map):
│  ├─ rating (number): 4 (1-5)
│  ├─ helpful (boolean): true
│  ├─ comment (string): "とてもわかりやすかった"
│  └─ timestamp (timestamp): 2026-09-24T10:40:00Z
└─ status (string): "active" (active/archived/flagged)
```

### aiUsageMetrics Collection

```firestore
companies/{companyId}/aiUsageMetrics/{metricId}
├─ date (date): 2026-09-24
├─ totalConversations (number): 45
├─ totalMessages (number): 234
├─ totalTokens (number): 45678
├─ totalCost (number): 1.67
├─ averageResponseTime (number): 2.3 (seconds)
├─ userSatisfaction (number): 4.2 (1-5)
├─ topicsRequested (array):
│  ├─ "Platform Tech": 15
│  ├─ "Operations": 12
│  └─ "GTM Strategy": 10
└─ errorCount (number): 3
```

---

## 🧪 テスト戦略

### Unit Tests

```dart
// test/features/ai_tutor/ai_tutor_screen_test.dart
group('AITutorScreen Tests', () {
  testWidgets('チャット画面が表示される', (WidgetTester tester) async {
    // テスト実装
  });

  testWidgets('メッセージが送信される', (WidgetTester tester) async {
    // テスト実装
  });

  testWidgets('Claude レスポンスが表示される', (WidgetTester tester) async {
    // テスト実装
  });

  testWidgets('エラーハンドリングが機能する', (WidgetTester tester) async {
    // テスト実装
  });

  testWidgets('レート制限が働く', (WidgetTester tester) async {
    // テスト実装
  });
});
```

### Integration Tests

```dart
// test/features/ai_tutor/ai_tutor_integration_test.dart
group('AITutor Integration Tests', () {
  testWidgets('質問送信～レスポンス表示フロー', (WidgetTester tester) async {
    // 1. チャット画面を開く
    // 2. 質問を入力
    // 3. 送信ボタンをタップ
    // 4. Claude API へのリクエスト確認
    // 5. レスポンス表示確認
    // 6. Firestore への保存確認
  });

  testWidgets('コンテキスト管理テスト', (WidgetTester tester) async {
    // モジュール・レベルコンテキストが正しく送信されるか
  });
});
```

### Performance Tests

```bash
# レスポンス時間測定
- 質問送信～レスポンス受信: < 3秒 (目標)
- UI 更新: < 100ms (目標)
- メッセージ表示: < 500ms (目標)

# メモリ使用量測定
- チャット画面メモリ: < 100MB (目標)
- 100メッセージ保持時: < 150MB (目標)
- メモリリーク: なし (必須)

# API コスト測定
- 平均トークン使用量: 250-400 (入出合計)
- 月額コスト: < $200 (目標)
```

---

## 📅 実装スケジュール（4週間）

### Week 1: 設計・準備 (2026-09-24 ~ 2026-10-01)

```
Day 1-2:
  └─ Claude API セットアップ
    ├─ API キー取得
    ├─ 秘密管理設定（環境変数・Secret Manager）
    ├─ テスト環境構築
    └─ API コスト監視ダッシュボード

Day 3-4:
  └─ UI/UX Mockup 作成
    ├─ Figma でデザイン
    ├─ インタラクションフロー
    ├─ レスポンシブ対応
    └─ ダークモード対応

Day 5-7:
  └─ Prompt エンジニアリング
    ├─ システム Prompt 作成
    ├─ Template 集作成（5-10パターン）
    ├─ Prompt テスト
    └─ 日本語最適化
```

**成果物**: 設計書 3 ドキュメント完成

---

### Week 2-3: 実装 (2026-10-02 ~ 2026-10-15)

```
Day 8-12:
  └─ Flutter UI 実装
    ├─ AITutorScreen 画面
    ├─ ChatMessageList ウィジェット
    ├─ ChatInputField ウィジェット
    ├─ ContextSidebar ウィジェット
    └─ テストコード

Day 13-17:
  └─ Cloud Functions 実装
    ├─ callAIChatbot 関数
    ├─ レート制限ロジック
    ├─ エラーハンドリング
    ├─ Firestore 保存
    └─ Unit テスト

Day 18-21:
  └─ Firestore 統合
    ├─ aiConversations コレクション
    ├─ aiUsageMetrics コレクション
    ├─ セキュリティルール
    └─ テストデータ準備
```

**成果物**: β版チャットボット動作確認

---

### Week 4: テスト・最適化 (2026-10-16 ~ 2026-10-22)

```
Day 22-24:
  └─ ユニット・統合テスト
    ├─ UI テスト 5 ケース
    ├─ Cloud Functions テスト
    ├─ Firestore 統合テスト
    └─ エラーハンドリングテスト

Day 25-26:
  └─ パフォーマンステスト
    ├─ レスポンス時間測定
    ├─ メモリ使用量測定
    ├─ API コスト測定
    └─ 最適化

Day 27-28:
  └─ Prompt チューニング
    ├─ 5 パターン実運用テスト
    ├─ ユーザーフィードバック
    ├─ 最適 Prompt 選定
    └─ ドキュメント更新
```

**成果物**:
- ✅ Claude API チャットボット v1.0
- ✅ テスト結果レポート
- ✅ API コスト分析
- ✅ 最適化レコメンデーション

---

## 💰 コスト見積もり

### Claude API 利用コスト

```
月額推定コスト:
  ユーザー数: 500
  月平均質問数: 5問/人
  総質問数: 2,500 質問/月

トークン計算:
  入力: 2,500 * 250トークン = 625,000 tokens
  出力: 2,500 * 350トークン = 875,000 tokens
  
費用:
  入力: 625,000 * ($3/1M) = $1.88
  出力: 875,000 * ($15/1M) = $13.13
  合計: 約 $15/月

(スケール時: $50-200/月 想定)
```

### インフラコスト

```
Cloud Functions:
  実行時間: 2,500 * 3秒 = 7,500秒/月
  メモリ: 512MB 設定
  推定: $0-1/月

Firestore:
  読み書き: 5,000 operations/月
  保存: 2,500 * 50KB = 125GB
  推定: $5-10/月

合計月額: 約 $20-30/月
```

---

## 📈 成功メトリクス

| メトリクス | ターゲット | 測定方法 |
|----------|----------|--------|
| 平均レスポンス時間 | < 3秒 | CloudTrace |
| ユーザー満足度 | ≥ 4.0/5 | アンケート |
| 再利用率 | ≥ 60% | Google Analytics |
| API エラー率 | < 1% | CloudMonitoring |
| テストカバレッジ | ≥ 80% | 自動測定 |

---

## 🚀 次ステップ

1. ✅ **本設計書のレビュー** (2026-09-17)
2. ⬜ **Claude API キー取得** (2026-09-24)
3. ⬜ **開発環境セットアップ** (2026-09-24～25)
4. ⬜ **UI Mockup 作成** (2026-09-26～27)
5. ⬜ **Prompt エンジニアリング** (2026-09-28～10-01)
6. ⬜ **実装開始** (2026-10-02)

---

**ステータス**: 📋 設計完成  
**最終更新**: 2026-09-17  
**次回更新**: 2026-09-24（Week 1 開始時）

