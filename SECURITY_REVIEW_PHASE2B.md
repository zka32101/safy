# Phase 2b セキュリティレビュー結果

## 実施日
2026-09-16

## レビュー対象
- `lib/features/learning_path/`
- `lib/features/qa_forum/`
- `lib/features/dashboard/`
- `functions/src/index.ts`

## 発見された問題と推奨事項

### 🔴 重大度: 高

#### 1. Firestore セキュリティルール未実装
**ファイル**: `functions/src/index.ts`
**問題**: Q&A フォーラムの Firestore ルールがクライアント側にのみ実装されている

**リスク**:
- 権限なしのユーザーが他の企業のデータにアクセス可能
- 質問・回答の削除・編集が可能
- データの改ざんが可能

**推奨事項**:
```firestore
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /companies/{companyId} {
      // 同じ企業のユーザーのみアクセス可能
      allow read: if request.auth.uid != null && 
                     (request.auth.uid in resource.data.employeeIds || 
                      resource.data.ownerId == request.auth.uid);
      allow write: if request.auth.uid == resource.data.ownerId;
      
      // Q&A フォーラム
      match /qaForum/{questionId} {
        allow read: if request.auth.uid != null;
        allow create: if request.auth.uid != null &&
                         request.resource.data.authorId == request.auth.uid &&
                         request.resource.data.companyId == companyId;
        allow update: if request.auth.uid == resource.data.authorId &&
                         !request.resource.data.diff(resource.data).affectedKeys().hasAny(['authorId', 'companyId', 'createdAt']);
        allow delete: if request.auth.uid == resource.data.authorId;
        
        match /answers/{answerId} {
          allow read: if request.auth.uid != null;
          allow create: if request.auth.uid != null &&
                           request.resource.data.authorId == request.auth.uid;
          allow update: if request.auth.uid == resource.data.authorId;
          allow delete: if request.auth.uid == resource.data.authorId;
        }
      }
    }
  }
}
```

#### 2. SQL インジェクション風の検索脆弱性
**ファイル**: `lib/features/qa_forum/qa_forum_screen.dart` L156-157

**問題**:
```dart
query = query.where('title', isGreaterThanOrEqualTo: _searchQuery)
    .where('title', isLessThan: _searchQuery + 'z');
```

複合インデックスが必要で、複数の where 条件があると Firestore の制限に抵触

**推奨事項**:
1. 単純な文字列マッチング検索は効率的ではない
2. 本番環境では全文検索 (Algolia, Elasticsearch) を使用
3. 当面は検索を無効化し、フィルタリングのみに限定

```dart
// クライアント側フィルタリングに変更
if (_searchQuery.isNotEmpty) {
  // サーバー側フィルタリング不可にして、クライアント側で実装
  questions = questions.where((q) => 
    q['title'].toString().toLowerCase().contains(_searchQuery.toLowerCase())
  ).toList();
}
```

### 🟡 重大度: 中

#### 3. レート制限・DDoS 対策なし
**ファイル**: `lib/features/qa_forum/qa_forum_screen.dart`

**問題**:
- 質問投稿時にレート制限がない
- 同じユーザーが短時間に大量投稿可能
- サーバーリソースの無駄遣いが可能

**推奨事項**:
```dart
// Cloud Functions に実装
export const submitQuestion = onCall(async (request) => {
  const { companyId, employeeId, title } = request.data;
  
  // レート制限チェック
  const lastQuestion = await db
    .collection('companies').doc(companyId)
    .collection('qaForum')
    .where('authorId', '==', employeeId)
    .orderBy('createdAt', 'desc')
    .limit(1)
    .get();
  
  if (lastQuestion.docs.length > 0) {
    const lastCreated = lastQuestion.docs[0].data().createdAt.toDate();
    const now = new Date();
    if ((now.getTime() - lastCreated.getTime()) < 5 * 60 * 1000) { // 5分以内
      throw new HttpsError('resource-exhausted', '質問は5分以上間隔をあけて投稿できます');
    }
  }
  
  // ... 質問作成処理
});
```

#### 4. エラーメッセージから情報漏洩
**ファイル**: `lib/features/qa_forum/qa_forum_screen.dart` L178

**問題**:
```dart
error: snapshot.error.toString(),
```

エラーオブジェクトの詳細が画面に表示される可能性

**推奨事項**:
```dart
error: 'データの読み込みに失敗しました',
// ログはサーバーサイドのみで記録
logger.error('Q&A読み込みエラー', snapshot.error);
```

#### 5. 権限チェック不足
**ファイル**: `lib/features/qa_forum/question_detail_screen.dart`

**問題**:
- 質問・回答の削除時に権限チェックがない
- 他のユーザーのデータを削除・編集可能

**推奨事項**:
```dart
// 削除処理に権限チェック追加
if (answer['authorId'] != employeeId) {
  throw HttpsError('permission-denied', '権限がありません');
}
```

### 🟢 重大度: 低

#### 6. 入力値検証不足
**ファイル**: `lib/features/qa_forum/qa_forum_screen.dart` L241

**問題**:
```dart
'title': title,
'description': description,
```

空文字列や過度に長い入力がチェックされていない

**推奨事項**:
```dart
if (title.isEmpty || title.length > 200) {
  throw Exception('タイトルは1～200文字である必要があります');
}

if (description.length > 1000) {
  throw Exception('説明は1000文字以下である必要があります');
}
```

#### 7. XSS 脆弱性（Dart/Flutter では低リスク）
**ファイル**: すべての画面表示

**問題**: ユーザー入力がそのまま表示される

**評価**: Dart のウィジェットベースレンダリングのため、XSS リスクは低い
**推奨事項**: HTMLレンダリング（WebView等）を使用する場合のみ対策が必要

#### 8. メモリリーク（TextEditingController）
**ファイル**: `lib/features/qa_forum/qa_forum_screen.dart` L19-24

**問題**: `_searchController` の dispose が正しく実装されている ✅

**評価**: 正しく実装されている

## Cloud Functions のセキュリティ

### ✅ 実装済み
- `completeLevelDiagnostic`: 認証チェック ✅
- `recordTrainingProgress`: 本人確認 ✅
- `submitLiveExam`: 認証チェック ✅

### ❌ 不足している
- Q&A フォーラムの Cloud Functions が未実装
- 質問投稿・回答投稿がクライアント直接実装

## テスト時の確認項目

### セキュリティテスト
- [ ] 他の企業のデータが見えないことを確認
- [ ] ログインなしではアクセスできないことを確認
- [ ] 権限なしの操作が拒否されることを確認
- [ ] 入力値検証が機能することを確認
- [ ] レート制限が機能することを確認

### 本番デプロイ前チェックリスト

**必須（本番デプロイ前に実装）:**
- [ ] Firestore セキュリティルール実装
- [ ] Q&A フォーラム用 Cloud Functions 実装
- [ ] レート制限実装
- [ ] エラーメッセージ調整（詳細情報削除）
- [ ] 権限チェック追加

**推奨（デプロイ後の改善）:**
- [ ] 全文検索ライブラリ導入
- [ ] ユーザー入力値の長さ制限
- [ ] 監視・ロギング強化
- [ ] DDoS 対策（Cloud Armor）

## セキュリティベストプラクティス

### Firestore
1. ✅ クライアント側での認証チェック
2. ❌ サーバー側での権限チェック（必須）
3. ✅ Timestamp の使用
4. ❌ 複合インデックスの事前作成

### Flutter
1. ✅ TextEditingController の dispose
2. ✅ エラーハンドリング
3. ⚠️ エラーメッセージの詳細度
4. ✅ ユーザーデータの保護

### Cloud Functions
1. ✅ 認証チェック
2. ✅ 入力検証
3. ⚠️ レート制限
4. ✅ ログ記録

## 改善プラン

### Phase 2b → 本番前（1週間）
1. **Day 1-2**: Firestore セキュリティルール実装テスト
2. **Day 3**: Q&A フォーラム Cloud Functions 実装
3. **Day 4-5**: セキュリティテスト実施
4. **Day 6**: 修正と検証
5. **Day 7**: 本番前最終確認

### Phase 2c（12月）
1. AI チューター API の認証
2. BigQuery 統合セキュリティ
3. 監視・ロギング強化

## 承認ステータス

- [ ] セキュリティレビュー完了
- [ ] すべての高重大度の問題が修正されている
- [ ] テストが完了している
- [ ] 本番デプロイ前のチェックリストが満たされている

---

**作成者**: Claude Code
**実施日**: 2026-09-16
**次回レビュー予定**: 本番デプロイ前
