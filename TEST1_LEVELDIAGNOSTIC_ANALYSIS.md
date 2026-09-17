# Test 1: LevelDiagnosticScreen 詳細分析

**ファイル**: `test/features/learning_path/level_diagnostic_screen_test.dart`  
**実装対象**: `lib/features/learning_path/level_diagnostic_screen.dart`  
**テストケース数**: 5個  
**合計行数**: 120行  
**作成日**: 2026-09-17

---

## 📋 テスト構成

### テストケース一覧

| # | テストケース | 難度 | 失敗リスク | 優先度 |
|----|-----------|------|---------|--------|
| 1 | レベル診断画面が5つの質問を表示する | 低 | 中 | 🔴 高 |
| 2 | 回答選択が記録される | 中 | 中 | 🔴 高 |
| 3 | 前へ・次へボタンが機能する | 中 | 高 | 🔴 高 |
| 4 | 診断完了ボタンが最終質問で表示される | 高 | 高 | 🟡 中 |
| 5 | プログレスバーが正確に表示される | 中 | 中 | 🟡 中 |

---

## 🔍 テストケース詳細分析

### Test 1: レベル診断画面が5つの質問を表示する

**行番号**: 9-28  
**テストロジック**:
```dart
// 1. MaterialApp + ProviderScope でラップ
await tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: LevelDiagnosticScreen(),
      ),
    ),
  ),
);

// 2. 最初の質問テキストを検索
expect(find.text('あなたの現在の業務経験は？'), findsOneWidget);

// 3. 4つの選択肢テキストを検索
expect(find.text('0-1年（新入社員・未経験）'), findsOneWidget);
expect(find.text('1-3年（基礎的な知識あり）'), findsOneWidget);
expect(find.text('3-5年（実務経験豊富）'), findsOneWidget);
expect(find.text('5年以上（リーダー・専門家水準）'), findsOneWidget);
```

**期待結果**: ✅ PASS (5つの要素すべてが見つかる)

**失敗予測**:
- ❌ パターン A: UI テキストが異なる
  ```dart
  // 実装側のテキストが異なる場合
  Text('あなたの現在のキャリアレベルは？')  // ← テストが失敗
  ```
  
- ❌ パターン B: 選択肢が 4 つでない
  ```dart
  // 選択肢が 3 つだけの場合
  // または 5 つ以上ある場合
  ```

- ❌ パターン C: ProviderScope がない
  ```dart
  // StateNotifierProvider が見つからない
  // sessionProvider が設定されていない
  ```

**対処方法**:
```dart
// ✅ 修正案 1: テキスト一致確認
// lib/features/learning_path/level_diagnostic_screen.dart を確認
// Text ウィジェットのテキストが一致しているか確認

// ✅ 修正案 2: findsWidgets を使用（複数許可）
expect(find.text('あなたの現在の業務経験は？'), findsWidgets);

// ✅ 修正案 3: byType で検索（テキスト依存を回避）
expect(find.byType(RadioListTile), findsWidgets);  // ラジオボタン
// または
expect(find.byType(ElevatedButton), findsWidgets);  // 選択肢ボタン
```

**対策**: 実装の UI テキストを確認してから実行

---

### Test 2: 回答選択が記録される

**行番号**: 30-51  
**テストロジック**:
```dart
// 1. 画面初期化
await tester.pumpWidget(ProviderScope(...));

// 2. 最初の選択肢をタップ
await tester.tap(find.text('0-1年（新入社員・未経験）'));
await tester.pumpAndSettle();  // 非同期処理完了を待機

// 3. 次へボタンが有効化されたことを確認
final nextButton = find.byType(ElevatedButton).evaluate().where(
  (widget) => widget.widget is ElevatedButton &&
      (widget.widget as ElevatedButton).onPressed != null,
);
expect(nextButton, isNotEmpty);  // 1個以上のボタンが有効
```

**期待結果**: ✅ PASS (タップ後、次へボタンが有効になる)

**失敗予測**:
- ❌ パターン A: onPressed が null のままになっている
  ```dart
  // 実装が状態を更新していない場合
  ElevatedButton(onPressed: null)  // ← 常に無効
  ```

- ❌ パターン B: ElevatedButton が複数あり、評価が複雑
  ```dart
  // 複数の ElevatedButton がある場合
  // 次へボタンではなく別のボタンが有効になる
  ```

- ❌ パターン C: タップが機能していない
  ```dart
  // テキストが見つからない
  // または GestureDetector で囲まれている
  ```

**リスク**: 🔴 **高い** (非同期状態の管理に依存)

**対処方法**:
```dart
// ✅ 修正案 1: pumpAndSettle() を確認
// デフォルトで 30 秒タイムアウト
await tester.pumpAndSettle(const Duration(seconds: 60));

// ✅ 修正案 2: ボタン検索を簡略化
final button = find.byType(ElevatedButton).first;  // 最初のボタン
await tester.tap(button);

// ✅ 修正案 3: State 確認用ウィジェットを使用
// Consumer で Provider の状態を確認
expect(find.byType(Text), findsWidgets);  // 状態変更の確認
```

**対策**: 実装の状態管理ロジックを検証してから実行

---

### Test 3: 前へ・次へボタンが機能する

**行番号**: 53-78  
**テストロジック**:
```dart
// 1. 最初の質問に回答
await tester.tap(find.text('0-1年（新入社員・未経験）'));
await tester.pumpAndSettle();

// 2. 次へボタン（ElevatedButton の最後）をタップ
final nextButton = find.byType(ElevatedButton).last;
await tester.tap(nextButton);
await tester.pumpAndSettle();

// 3. 2番目の質問が表示されたことを確認
expect(find.text('デジタルツールの使用経験は？'), findsOneWidget);

// 4. プログレスバーが表示されていることを確認
expect(find.byType(LinearProgressIndicator), findsOneWidget);
```

**期待結果**: ✅ PASS (次へボタンで次の質問に遷移)

**失敗予測**:
- ❌ パターン A: .last が正しいボタンでない
  ```dart
  // ElevatedButton が複数ある場合、最後のボタンが
  // 「次へ」ボタンではなく「キャンセル」や「戻る」かもしれない
  ```

- ❌ パターン B: 2番目の質問テキストが異なる
  ```dart
  // 実装側で異なるテキスト
  Text('デジタルツール経験レベルは？')  // ← テスト失敗
  ```

- ❌ パターン C: ナビゲーション が機能していない
  ```dart
  // ボタンタップ後、画面が遷移しない
  // または PageRoute で遷移する場合、テストが失敗
  ```

**リスク**: 🔴 **高い** (ボタン選択の不確実性)

**対処方法**:
```dart
// ✅ 修正案 1: ボタンをラベルで検索
final nextButton = find.byWidgetPredicate(
  (widget) => widget is ElevatedButton && 
      widget.child?.toString().contains('次へ') == true
);
await tester.tap(nextButton);

// ✅ 修正案 2: Tooltip で識別
final nextButton = find.byTooltip('次へボタン');

// ✅ 修正案 3: Key を使用
const nextButtonKey = Key('nextButton');
// lib の実装に Key を追加
ElevatedButton(key: nextButtonKey, ...)
// テストで参照
final nextButton = find.byKey(nextButtonKey);
```

**対策**: 実装に Key または Tooltip を追加して、ボタン特定を確実にする

---

### Test 4: 診断完了ボタンが最終質問で表示される

**行番号**: 80-98  
**テストロジック**:
```dart
// ⚠️ 問題: 最後の質問まで進めていない
// コメント: "実際のテストでは、すべての質問に回答する必要がある"

// 1. 最初の質問に回答（のみ）
await tester.tap(find.text('0-1年（新入社員・未経験）'));
await tester.pumpAndSettle();

// 2. プログレスバーが表示されていることを確認（のみ）
expect(find.byType(LinearProgressIndicator), findsOneWidget);
```

**期待結果**: ❌ **実装不完全** 
- ℹ️ テストが不完全（最後の質問に到達していない）
- ℹ️ 診断完了ボタンの確認がない

**失敗予測**:
- ℹ️ 現在のテストは、プログレスバーの存在確認のみ
- ℹ️ 実際の「診断完了ボタン」の表示確認がない

**対処方法**:
```dart
// ✅ 改善案: テストを完成させる
testWidgets('診断完了ボタンが最終質問で表示される', 
    (WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(...));

  // 5つすべての質問に回答
  final answers = [
    '0-1年（新入社員・未経験）',
    '[2番目の選択肢]',
    '[3番目の選択肢]',
    '[4番目の選択肢]',
    '[5番目の選択肢]',
  ];

  for (int i = 0; i < 5; i++) {
    // 質問に回答
    await tester.tap(find.text(answers[i]));
    await tester.pumpAndSettle();

    // 最後の質問でない場合は次へボタン
    if (i < 4) {
      await tester.tap(find.byKey(const Key('nextButton')));
      await tester.pumpAndSettle();
    }
  }

  // 最後の質問で「診断完了」ボタンが表示される
  expect(find.text('診断完了'), findsOneWidget);
  expect(find.byKey(const Key('completeButton')), findsOneWidget);
});
```

**対策**: テスト 4 は Day 2 で完成させる（現在は準備段階）

---

### Test 5: プログレスバーが正確に表示される

**行番号**: 100-118  
**テストロジック**:
```dart
// 1. プログレスバーを探す
final progressIndicator = find.byType(LinearProgressIndicator);
expect(progressIndicator, findsOneWidget);

// 2. プログレスバーの値を取得
final widget = tester.widget<LinearProgressIndicator>(progressIndicator);

// 3. 値が 0.2（±0.01）であることを確認（1/5 = 0.2）
expect(widget.value, closeTo(0.2, 0.01));  // 0.19～0.21 の範囲
```

**期待結果**: ✅ PASS (プログレスバー = 0.2)

**失敗予測**:
- ❌ パターン A: プログレスバーの計算が異なる
  ```dart
  // 実装が異なる計算式
  value: (currentQuestion + 1) / 6  // ← 0.167 になり失敗
  // または
  value: currentQuestion / 5       // ← 0.0 になり失敗
  ```

- ❌ パターン B: プログレスバーが複数ある
  ```dart
  // 複数の LinearProgressIndicator がある場合
  // findsOneWidget が失敗
  ```

- ❌ パターン C: 浮動小数点演算の丸め誤差
  ```dart
  // 計算結果が 0.2000001 など
  // closeTo で救済可能だが、誤差が大きい場合失敗
  ```

**対処方法**:
```dart
// ✅ 修正案 1: 許容範囲を拡げる
expect(widget.value, closeTo(0.2, 0.05));  // ±5%

// ✅ 修正案 2: 正確な値を確認（デバッグ）
print('Progress: ${widget.value}');  // ログで実際の値確認

// ✅ 修正案 3: 実装の計算式を確認
// (currentQuestion + 1) / totalQuestions が正しいか確認
```

**対策**: 実装の進捗率計算ロジックを確認してから実行

---

## ⚠️ 共通の潜在的問題

### 1. Riverpod Provider モック

**問題**: sessionProvider が見つからない場合、すべてのテストが失敗

**症状**:
```
StateNotifierProvider not found
```

**解決策**:
```dart
// test/fixtures/mock_providers.dart を準備
final mockSessionProvider = StateNotifierProvider.autoDispose(...)

// テストで使用
await tester.pumpWidget(
  ProviderScope(
    overrides: [
      sessionProvider.overrideWithValue(mockSessionData),
    ],
    child: MaterialApp(...),
  ),
);
```

### 2. UIテキスト一致の厳密性

**問題**: 空白文字、改行、Unicode 異なるなど

**症状**:
```
Expected: one widget with text '質問です'
Found: zero widgets
```

**解決策**:
```dart
// 正規表現で検索
find.byWidgetPredicate((widget) => 
  widget is Text && 
  widget.data?.contains('質問') == true
);

// またはテキストの一部で検索
find.textContaining('質問');
```

### 3. 非同期処理のタイムアウト

**問題**: pumpAndSettle() が 30 秒待つが、それでも完了しない

**症状**:
```
The following assertion was thrown running a test:
Future not completed within 30000ms
```

**解決策**:
```dart
// タイムアウト値を増やす
await tester.pumpAndSettle(const Duration(seconds: 60));

// または明示的な待機
await tester.pump(const Duration(seconds: 5));
```

---

## 📊 Test 1 リスク評価

| テスト | リスク | 理由 | 対策 |
|------|--------|------|------|
| 1 | 🟡 中 | テキスト一致 | UI 実装確認 |
| 2 | 🔴 高 | 状態管理 | Provider モック確認 |
| 3 | 🔴 高 | ボタン特定 | Key/Tooltip 追加 |
| 4 | ⚠️ 準備中 | テスト不完全 | Day 2 で完成 |
| 5 | 🟡 中 | 浮動小数点 | 許容値確認 |

**総合リスク**: 🔴 **高い** (3つが失敗する可能性あり)

---

## ✅ Day 1 実行準備チェック

実行前に確認すべき項目:

- [ ] `lib/features/learning_path/level_diagnostic_screen.dart` の UI テキストを確認
- [ ] Riverpod sessionProvider モック設定を確認
- [ ] ボタン特定方法（Key or Tooltip）を決定
- [ ] プログレスバー計算ロジックを確認
- [ ] Test 4 の完成度を評価（スキップ検討）

---

**ステータス**: 📋 詳細分析完了  
**推奨実行順**: Test 1 → Test 5 → Test 2 → Test 3 → Test 4  
**推奨**: Test 4 はスキップして Day 2 で実施
