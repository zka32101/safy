/// レベル診断結果・受講履歴をもとにしたモジュール推薦ロジック。
///
/// [level_diagnostic_screen.dart] と [learning_path_screen.dart] の
/// 両方から参照される共通ロジック（Firestore/Riverpodに依存しない純粋な関数群）。

/// 診断の質問カテゴリと、モジュール推薦時のキーワードマッチングに使うキーワード群。
class DiagnosticCategory {
  final String label;
  final List<String> keywords;

  const DiagnosticCategory(this.label, this.keywords);
}

/// 質問インデックス(0-4) → カテゴリ定義。
/// `level_diagnostic_screen.dart` の `diagnosticQuestions` の並び順と対応している。
const List<DiagnosticCategory> kDiagnosticQuestionCategories = [
  DiagnosticCategory('業務経験', ['基礎', '入門', 'オリエンテーション', '基本']),
  DiagnosticCategory('デジタルツール活用', ['ツール', 'デジタル', 'システム', 'IT']),
  DiagnosticCategory('チームマネジメント', ['マネジメント', 'リーダー', 'チーム運営']),
  DiagnosticCategory('データ分析', ['データ', '分析', 'レポート']),
  DiagnosticCategory('コミュニケーション', ['コミュニケーション', 'プレゼン', '発表']),
];

/// 弱点分野ごとの推薦理由テンプレート。
const Map<String, String> kWeakCategoryReasons = {
  '業務経験': '業務経験が浅いため、基礎モジュールをお勧めします',
  'デジタルツール活用': 'デジタルツールの活用経験が少ないため、ツール系モジュールをお勧めします',
  'チームマネジメント': 'チーム運営・マネジメントの経験を補うモジュールをお勧めします',
  'データ分析': 'データ分析スキルの強化につながるモジュールをお勧めします',
  'コミュニケーション': 'コミュニケーション・プレゼンスキルを高めるモジュールをお勧めします',
};

/// 回答（質問インデックス→選択肢インデックス 0-3）から弱点分野を推定する。
/// 選択肢インデックスが低い(0 or 1)ほど経験・スキルが浅いと判断する。
List<String> determineWeakCategories(Map<int, int> answers) {
  final weak = <String>[];
  for (var i = 0; i < kDiagnosticQuestionCategories.length; i++) {
    final answer = answers[i];
    if (answer != null && answer <= 1) {
      weak.add(kDiagnosticQuestionCategories[i].label);
    }
  }
  return weak;
}

/// Firestoreに保存された診断結果の `answers` フィールド
/// （キーが文字列の Map になっている場合がある）を `Map<int, int>` に正規化する。
Map<int, int> normalizeDiagnosticAnswers(dynamic rawAnswers) {
  final result = <int, int>{};
  if (rawAnswers is Map) {
    rawAnswers.forEach((key, value) {
      final index = int.tryParse(key.toString());
      final answer =
          value is num ? value.toInt() : int.tryParse(value.toString());
      if (index != null && answer != null) {
        result[index] = answer;
      }
    });
  }
  return result;
}

/// 特定モジュールに対する、社員の受講履歴の要約。
class ModuleProgressSummary {
  final bool isPassed;
  final int maxScore;
  final int lessonsCompleted;

  const ModuleProgressSummary({
    required this.isPassed,
    required this.maxScore,
    required this.lessonsCompleted,
  });
}

/// 推薦モジュールとその推薦理由。
class RecommendedModule {
  final Map<String, dynamic> module;
  final String reason;

  const RecommendedModule({required this.module, required this.reason});
}

class _ScoredModule {
  final Map<String, dynamic> module;
  final int score;
  final String reason;

  const _ScoredModule({
    required this.module,
    required this.score,
    required this.reason,
  });
}

/// 診断結果（弱点分野）と受講履歴（進捗が低い/未受講）をもとに、
/// [modules] の中から優先的に受講すべきモジュールを選定する。
///
/// - 弱点分野のキーワードにマッチするモジュールを優先
/// - 未受講・進捗が低い（合格していない）モジュールを優先
/// - 既に合格済みのモジュールは推薦対象から除外
List<RecommendedModule> buildModuleRecommendations({
  required List<Map<String, dynamic>> modules,
  required List<String> weakCategories,
  required Map<String, ModuleProgressSummary> progressByModuleId,
  int limit = 4,
}) {
  final scored = <_ScoredModule>[];

  for (final module in modules) {
    final id = module['id'] as String? ?? '';
    final progress = progressByModuleId[id];

    // 合格済みのモジュールはおすすめ対象から除外
    if (progress != null && progress.isPassed) {
      continue;
    }

    final title = module['title'] as String? ?? '';
    final category = module['category'] as String? ?? '';
    final description = module['description'] as String? ?? '';
    final searchText = '$title $category $description';

    final matchedCategories = weakCategories.where((weak) {
      final def = kDiagnosticQuestionCategories.firstWhere(
        (c) => c.label == weak,
        orElse: () => const DiagnosticCategory('', []),
      );
      return def.keywords.any((keyword) => searchText.contains(keyword));
    }).toList();

    var score = 0;
    final reasons = <String>[];

    if (matchedCategories.isNotEmpty) {
      score += 2;
      final reason = kWeakCategoryReasons[matchedCategories.first];
      if (reason != null) {
        reasons.add(reason);
      }
    }

    if (progress == null) {
      score += 1;
      reasons.add('まだ受講していないモジュールです');
    } else if (!progress.isPassed) {
      score += 1;
      reasons.add('受講途中のため、修了を目指しましょう（現在のスコア: ${progress.maxScore}点）');
    }

    if (score == 0) {
      continue;
    }

    scored.add(_ScoredModule(
      module: module,
      score: score,
      reason: reasons.join('。'),
    ));
  }

  scored.sort((a, b) => b.score.compareTo(a.score));

  return scored
      .take(limit)
      .map((s) => RecommendedModule(module: s.module, reason: s.reason))
      .toList();
}
