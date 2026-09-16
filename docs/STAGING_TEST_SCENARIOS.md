# Tier 1 Training ステージング環境テストシナリオ

**テスト目的**: Sep 16-22 の学習期間を本番環境と同じ条件でシミュレート  
**テスト期間**: Sep 15（本番リハーサル）  
**対象者**: QA チーム 5-10 名

---

## シナリオ 1: Happy Path（正常フロー）

**期待結果**: すべてのモジュール完了 → 修了証発行

### 実行手順

1. **ログイン**
   ```
   メール: test-user-001@staging.safy.jp
   パスワード: StagingTest123!
   ```

2. **ホーム画面確認**
   - [ ] Tier 1 Training ナビゲーションカード表示
   - [ ] 「Sep 16-22 自習期間」テキスト表示
   - [ ] 「4つのモジュール、計16時間」表示

3. **Training Dashboard へ遷移**
   - [ ] 4つのモジュールが表示される
   - [ ] 期限カウントダウン表示（0日00時間）

4. **Module 1: Platform Tech 完了**
   ```
   - レッスン 4 個視聴完了
   - クイズ 5 問すべて実施
   - スコア ≥ 80% で合格
   ```
   - [ ] 進捗バーが 25% に
   - [ ] ✅ 修了バッジは表示されない（次のステップで表示）

5. **Module 2-4: 同じフロー**
   ```
   各モジュール:
   - レッスン 4 個視聴
   - クイズ 5 問実施
   - スコア ≥ 80%
   ```

6. **4つ目のモジュール完了直後**
   - [ ] プッシュ通知が届く: 「すべてのモジュールが完了しました」
   - [ ] Firestore trainingCertificates に新規レコード作成
   - [ ] 修了証番号（CERT-20260916-XXXXXX）確認

7. **修了証確認**
   - [ ] Certificates 画面に Tier 1 Training 修了証が表示
   - [ ] 発行日時が正確

**テスト時間**: 約 60 分  
**失敗時の対応**: ステップ X で停止して、logs を確認

---

## シナリオ 2: Partial Completion（部分完了）

**期待結果**: 2 つのモジュールのみ完了 → 修了証は発行されない

### 実行手順

1. **ログイン**
   ```
   メール: test-user-002@staging.safy.jp
   ```

2. **Module 1 + Module 2 のみ完了**
   ```
   - Platform Tech: クイズ 80% 合格
   - Operations: クイズ 80% 合格
   - Content Production: スキップ（完了しない）
   - GTM Strategy: スキップ（完了しない）
   ```

3. **確認項目**
   - [ ] Training Dashboard で進捗 50% 表示
   - [ ] プッシュ通知 0 件
   - [ ] trainingCertificates に新規レコード作成されない

**テスト時間**: 約 30 分  
**結論**: 4つ全て完了しないと修了証は発行されない ✅

---

## シナリオ 3: Low Score（不合格）

**期待結果**: スコア < 80% で不合格 → リトライ

### 実行手順

1. **ログイン**
   ```
   メール: test-user-003@staging.safy.jp
   ```

2. **Module 1 で故意に低スコア**
   ```
   - クイズ 5 問中 3 問だけ正答（60% = 不合格）
   ```

3. **確認項目**
   - [ ] スコア 60% で「不合格」表示
   - [ ] 修了バッジなし
   - [ ] リトライ可能な状態

4. **リトライ実施**
   ```
   - もう一度クイズ実施
   - スコア ≥ 80% で合格
   ```

5. **確認項目**
   - [ ] 新しいスコア（80%+）が記録される
   - [ ] passed フラグが true に更新
   - [ ] 修了バッジが表示される

**テスト時間**: 約 20 分  
**結論**: リトライで単位取得可能 ✅

---

## シナリオ 4: Network Failure（ネットワーク障害）

**期待結果**: 通信復旧後、自動リトライで成功

### 実行手順

1. **ログイン直後、機内モード ON**
   ```
   - ホーム画面は表示済み
   - Training Dashboard へ遷移試行
   ```

2. **オフライン状態で遷移**
   - [ ] エラーメッセージ表示（「ネットワーク接続を確認してください」）

3. **機内モード OFF（通信復旧）**
   - [ ] リトライボタンをタップ
   - [ ] Training Dashboard 遷移成功

4. **クイズ実施中の通信切断**
   ```
   - クイズ途中で機内モード ON
   - クイズ回答送信試行
   ```

5. **確認項目**
   - [ ] Cloud Functions submitQuizAttempt の自動リトライ（最大 3 回）
   - [ ] 通信復旧後、自動で再送信
   - [ ] スコアが正確に記録される

**テスト時間**: 約 15 分  
**結論**: リトライロジックが正常に動作 ✅

---

## シナリオ 5: Concurrent Users（並行ユーザー）

**期待結果**: 複数ユーザーが同時にクイズ実施 → Firestore quota エラーなし

### 実行手順

1. **5 ユーザー同時ログイン**
   ```
   test-user-004 ~ test-user-008 (複数デバイスまたはブラウザ)
   ```

2. **同時にクイズ実施**
   ```
   - 全ユーザーが Platform Tech クイズ実施
   - 同時に recordTrainingProgress 呼び出し
   ```

3. **Cloud Monitoring 確認**
   - [ ] Firestore 読み書き/秒が正常範囲（< 100 ops/sec）
   - [ ] Cloud Functions invocation 成功率 100%
   - [ ] Quota exceeded エラー 0 件

4. **スコア正確性確認**
   ```sql
   SELECT employeeId, moduleId, score, passed, COUNT(*)
   FROM trainingAttempts
   WHERE employeeId IN ('test-user-004', 'test-user-005', ...)
   GROUP BY employeeId, moduleId, score, passed
   ```
   - [ ] 各ユーザーのスコアが独立している
   - [ ] 重複・混在なし

**テスト時間**: 約 20 分  
**結論**: 並行処理が安定している ✅

---

## シナリオ 6: Deadline Edge Case（期限境界）

**期待結果**: Sep 22 23:59 JST のタイムゾーン処理が正確

### 実行手順

1. **サーバー時刻を Sep 22 23:58 に設定**
   ```bash
   sudo date -s "2026-09-22 23:58:00+0900"
   ```

2. **ユーザーがクイズ提出**
   ```
   - recordTrainingProgress 呼び出し
   ```

3. **確認項目**
   - [ ] trainingAttempts に attemptedAt が Sep 22 23:58 で記録
   - [ ] passed = true の場合、修了証発行

4. **時刻を Sep 23 00:01 に進める**
   ```bash
   sudo date -s "2026-09-23 00:01:00+0900"
   ```

5. **checkTrainingDeadline トリガー**
   - [ ] trainingDeadlineStatus に新規レコード
   - [ ] incompleteModules にモジュール ID が記録

**テスト時間**: 約 10 分  
**結論**: JST タイムゾーン処理が正確 ✅

---

## シナリオ 7: Certificate Generation Load（修了証生成の負荷テスト）

**期待結果**: 複数ユーザーの修了証同時生成も正常

### 実行手順

1. **5 ユーザーが同時に 4 つ目のモジュール完了**
   ```
   test-user-009 ~ test-user-013
   ```

2. **issueTrainingCertificate 同時実行**
   - [ ] 各ユーザーに固有の修了証番号生成
   - [ ] 重複なし

3. **確認項目**
   ```sql
   SELECT certificateNumber, COUNT(*)
   FROM trainingCertificates
   GROUP BY certificateNumber
   HAVING COUNT(*) > 1;
   ```
   - [ ] 重複した証書番号なし
   - [ ] 各証書番号が固有（CERT-20260916-XXXXXX）

4. **プッシュ通知の正確性**
   - [ ] 5 つの通知がすべて到達
   - [ ] タイトル・本文が正確

**テスト時間**: 約 15 分  
**結論**: 修了証生成の並行処理が安全 ✅

---

## テスト実行チェックリスト

```
[ ] シナリオ 1: Happy Path ✅
[ ] シナリオ 2: Partial Completion ✅
[ ] シナリオ 3: Low Score & Retry ✅
[ ] シナリオ 4: Network Failure ✅
[ ] シナリオ 5: Concurrent Users ✅
[ ] シナリオ 6: Deadline Edge Case ✅
[ ] シナリオ 7: Certificate Generation Load ✅

【総合判定】: ✅ PASS / ❌ FAIL
```

---

## テスト報告書テンプレート

```
テスト日時: ____年____月____日
テスト実施者: _________________________
テスト環境: Staging (Firebase Project: safy-staging)

【実行結果】
シナリオ 1: ✅ PASS / ❌ FAIL
  - 詳細: ___________

シナリオ 2: ✅ PASS / ❌ FAIL
  - 詳細: ___________

【発見された課題】
1. 課題1: ___________________
   対応: ___________________
   優先度: 🔴 High / 🟡 Medium / 🟢 Low

【パフォーマンス測定】
- Cloud Functions 平均実行時間: ____ms
- Firestore 読み取り/秒: ____
- API 可用性: ___%

【総合判定】
✅ 本番リリース OK / ⚠️  要改善 / ❌ リリース不可

【サイン】
テスト実施者: _________________ 日時: _______
監督者: _________________ 日時: _______
```

---

**作成者**: QA Team  
**最終更新**: Sep 15, 2026  
**実行期限**: Sep 15 18:00 JST
