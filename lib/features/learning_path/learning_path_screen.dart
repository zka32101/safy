import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/session_provider.dart';
import '../../providers/firebase_providers.dart';
import '../../widgets/error_retry_view.dart';
import '../../data/models/training_progress_model.dart';
import 'diagnostic_recommendation.dart';

/// 学習パスレコメンデーション画面：診断結果に基づく個別学習計画
class LearningPathScreen extends ConsumerStatefulWidget {
  final String? userLevel; // beginner, intermediate, advanced

  const LearningPathScreen({
    super.key,
    this.userLevel,
  });

  @override
  ConsumerState<LearningPathScreen> createState() =>
      _LearningPathScreenState();
}

class _LearningPathScreenState extends ConsumerState<LearningPathScreen> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    if (!session.isSignedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('学習パス')),
        body: const Center(child: Text('ログインが必要です')),
      );
    }

    return _LearningPathContent(
      companyId: session.employee!.companyId,
      employeeId: session.employee!.id,
      userLevel: widget.userLevel,
    );
  }
}

class _LearningPathContent extends ConsumerStatefulWidget {
  final String companyId;
  final String employeeId;
  final String? userLevel;

  const _LearningPathContent({
    required this.companyId,
    required this.employeeId,
    this.userLevel,
  });

  @override
  ConsumerState<_LearningPathContent> createState() => _LearningPathContentState();
}

class _LearningPathContentState extends ConsumerState<_LearningPathContent> {
  late Future<Map<String, dynamic>> _learningPathFuture;

  @override
  void initState() {
    super.initState();
    _learningPathFuture = _loadLearningPath();
  }

  Future<Map<String, dynamic>> _loadLearningPath() async {
    try {
      // ユーザーレベルの取得（診断を未実施の場合はデフォルト）
      String userLevel = widget.userLevel ?? 'intermediate';
      final firestore = ref.read(firestoreProvider);

      // Firestore から該当レベルの推奨学習パスを取得
      final pathSnapshot = await firestore
          .collection('learningPaths')
          .doc(userLevel)
          .get();

      if (!pathSnapshot.exists) {
        return {
          'level': userLevel,
          'title': 'カスタム学習パス',
          'modules': [],
        };
      }

      final pathData = pathSnapshot.data() as Map<String, dynamic>;

      // 推奨モジュールを取得
      final recommendedModuleIds =
          List<String>.from(pathData['recommendedModuleIds'] as List? ?? []);

      final modules = <Map<String, dynamic>>[];
      for (final moduleId in recommendedModuleIds) {
        final moduleSnap = await firestore
            .collection('modules')
            .doc(moduleId)
            .get();

        if (moduleSnap.exists) {
          modules.add({
            'id': moduleId,
            ...moduleSnap.data() as Map<String, dynamic>,
          });
        }
      }

      // 診断結果（回答パターン）から弱点分野を推定
      List<String> weakCategories = [];
      try {
        final diagnosticsSnapshot = await firestore
            .collection('companies')
            .doc(widget.companyId)
            .collection('employeeDiagnostics')
            .where('employeeId', isEqualTo: widget.employeeId)
            .orderBy('completedAt', descending: true)
            .limit(1)
            .get();

        if (diagnosticsSnapshot.docs.isNotEmpty) {
          final diagnosticData = diagnosticsSnapshot.docs.first.data();
          final answers =
              normalizeDiagnosticAnswers(diagnosticData['answers']);
          weakCategories = determineWeakCategories(answers);
        }
      } catch (_) {
        // 診断結果が未実施/取得失敗でも学習パス自体の表示は継続する
      }

      // 過去の受講履歴（進捗が低いモジュール・未受講モジュールの判定に使用）
      final progressByModuleId = <String, ModuleProgressSummary>{};
      try {
        final attemptsSnapshot = await firestore
            .collection('companies')
            .doc(widget.companyId)
            .collection('trainingAttempts')
            .where('employeeId', isEqualTo: widget.employeeId)
            .get();

        for (final doc in attemptsSnapshot.docs) {
          final attempt = TrainingProgress.fromMap(doc.data());
          final existing = progressByModuleId[attempt.moduleId];
          // 同一モジュールに複数の受講記録がある場合は、合格済み・高スコアの記録を優先する
          if (existing == null ||
              (attempt.isPassed && !existing.isPassed) ||
              attempt.maxScore > existing.maxScore) {
            progressByModuleId[attempt.moduleId] = ModuleProgressSummary(
              isPassed: attempt.isPassed,
              maxScore: attempt.maxScore,
              lessonsCompleted: attempt.lessonsCompleted,
            );
          }
        }
      } catch (_) {
        // 受講履歴が取得できなくても、おすすめ無しで学習パスの表示は継続する
      }

      final recommendations = buildModuleRecommendations(
        modules: modules,
        weakCategories: weakCategories,
        progressByModuleId: progressByModuleId,
      );

      return {
        'level': userLevel,
        'title': pathData['title'] as String? ?? '学習パス',
        'description': pathData['description'] as String? ?? '',
        'estimatedHours': pathData['estimatedHours'] as int? ?? 0,
        'modules': modules,
        'weakCategories': weakCategories,
        'recommendations': recommendations,
      };
    } catch (e) {
      return {
        'level': widget.userLevel ?? 'intermediate',
        'title': '学習パス読み込みエラー',
        'error': e.toString(),
        'modules': [],
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学習パス'),
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _learningPathFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ErrorRetryView(
              message: snapshot.error.toString(),
              onRetry: () => setState(() {
                _learningPathFuture = _loadLearningPath();
              }),
            );
          }

          final pathData = snapshot.data ?? {};
          final modules = List<Map<String, dynamic>>.from(
            pathData['modules'] as List? ?? [],
          );
          final recommendations = List<RecommendedModule>.from(
            pathData['recommendations'] as List? ?? [],
          );

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderCard(context, pathData),
                if (recommendations.isNotEmpty)
                  _buildRecommendationSection(context, recommendations),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '推奨学習モジュール',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (modules.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          alignment: Alignment.center,
                          child: const Text(
                            'このレベル向けのモジュールはまだ登録されていません',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ..._buildModuleCards(context, modules),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    Map<String, dynamic> pathData,
  ) {
    final levelLabels = {
      'beginner': '初級者向け',
      'intermediate': '中級者向け',
      'advanced': '上級者向け',
    };

    final levelColors = {
      'beginner': Colors.green,
      'intermediate': Colors.blue,
      'advanced': Colors.purple,
    };

    final level = pathData['level'] as String? ?? 'intermediate';
    final color = levelColors[level] ?? Colors.blue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withOpacity(0.7)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pathData['title'] as String? ?? '学習パス',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              levelLabels[level] ?? level,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if ((pathData['description'] as String?)?.isNotEmpty ?? false)
            Text(
              pathData['description'] as String,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          if (((pathData['estimatedHours'] as int?) ?? 0) > 0) ...[
            const SizedBox(height: 8),
            Text(
              '推定学習時間：${pathData['estimatedHours']}時間',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 診断結果（弱点分野）と過去の受講履歴（進捗が低い／未受講のモジュール）を
  /// もとにした「あなたへのおすすめ」セクション
  Widget _buildRecommendationSection(
    BuildContext context,
    List<RecommendedModule> recommendations,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                'あなたへのおすすめ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '診断結果とこれまでの受講状況をもとに優先度の高いモジュールを表示しています',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          ...recommendations.map(
            (recommendation) =>
                _buildRecommendationCard(context, recommendation),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(
    BuildContext context,
    RecommendedModule recommendation,
  ) {
    final module = recommendation.module;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        child: InkWell(
          onTap: () {
            // モジュール画面への遷移処理
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        module['title'] as String? ?? 'モジュール',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward, color: Colors.grey[400]),
                  ],
                ),
                if (recommendation.reason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: Colors.amber[800]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          recommendation.reason,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildModuleCards(
    BuildContext context,
    List<Map<String, dynamic>> modules,
  ) {
    return modules.asMap().entries.map((entry) {
      final index = entry.key;
      final module = entry.value;

      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Material(
          child: InkWell(
            onTap: () {
              // モジュール画面への遷移処理
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              module['title'] as String? ?? 'モジュール',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if ((module['description'] as String?)
                                    ?.isNotEmpty ??
                                false)
                              Text(
                                module['description'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward,
                          color: Colors.grey[400]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if ((module['duration'] as String?)?.isNotEmpty ??
                          false)
                        Chip(
                          label: Text(module['duration'] as String),
                          backgroundColor: Colors.blue.withOpacity(0.1),
                          labelStyle: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(width: 8),
                      if ((module['category'] as String?)?.isNotEmpty ??
                          false)
                        Chip(
                          label: Text(module['category'] as String),
                          backgroundColor: Colors.green.withOpacity(0.1),
                          labelStyle: TextStyle(
                            color: Colors.green[700],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}
