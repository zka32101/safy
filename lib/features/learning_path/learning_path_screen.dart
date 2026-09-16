import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/session_provider.dart';
import '../../widgets/error_retry_view.dart';

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

    return session.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('学習パス')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => Scaffold(
        appBar: AppBar(title: const Text('学習パス')),
        body: ErrorRetryView(
          error: err.toString(),
          onRetry: () => ref.refresh(sessionProvider),
        ),
      ),
      data: (sessionData) {
        if (sessionData == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('学習パス')),
            body: const Center(child: Text('ログインが必要です')),
          );
        }

        return _LearningPathContent(
          companyId: sessionData.companyId,
          employeeId: sessionData.userId,
          userLevel: widget.userLevel,
        );
      },
    );
  }
}

class _LearningPathContent extends StatefulWidget {
  final String companyId;
  final String employeeId;
  final String? userLevel;

  const _LearningPathContent({
    required this.companyId,
    required this.employeeId,
    this.userLevel,
  });

  @override
  State<_LearningPathContent> createState() => _LearningPathContentState();
}

class _LearningPathContentState extends State<_LearningPathContent> {
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

      // Firestore から該当レベルの推奨学習パスを取得
      final pathSnapshot = await FirebaseFirestore.instance
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
        final moduleSnap = await FirebaseFirestore.instance
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

      return {
        'level': userLevel,
        'title': pathData['title'] as String? ?? '学習パス',
        'description': pathData['description'] as String? ?? '',
        'estimatedHours': pathData['estimatedHours'] as int? ?? 0,
        'modules': modules,
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
              error: snapshot.error.toString(),
              onRetry: () => setState(() {
                _learningPathFuture = _loadLearningPath();
              }),
            );
          }

          final pathData = snapshot.data ?? {};
          final modules = List<Map<String, dynamic>>.from(
            pathData['modules'] as List? ?? [],
          );

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderCard(context, pathData),
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
          if ((pathData['estimatedHours'] as int?) ?? 0 > 0) ...[
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
