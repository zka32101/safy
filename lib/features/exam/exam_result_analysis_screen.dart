import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/firebase_providers.dart';
import '../../services/firestore_paths.dart';
import '../../widgets/error_retry_view.dart';

/// 試験結果分析画面：分野別・設問別に正答率を分析し、弱点分野を可視化する。
/// submitLiveExam（Cloud Functions）が examAttempts ドキュメントに保存した
/// categoryBreakdown / results を読み取って表示する。
class ExamResultAnalysisScreen extends ConsumerStatefulWidget {
  final String companyId;
  final String examAttemptId;

  const ExamResultAnalysisScreen({
    super.key,
    required this.companyId,
    required this.examAttemptId,
  });

  @override
  ConsumerState<ExamResultAnalysisScreen> createState() =>
      _ExamResultAnalysisScreenState();
}

class _ExamResultAnalysisScreenState
    extends ConsumerState<ExamResultAnalysisScreen> {
  // FutureBuilderのfutureはbuild()内で再生成すると無限リビルドの原因になるため、
  // フィールドにキャッシュして保持する。
  late Future<DocumentSnapshot<Map<String, dynamic>>> _attemptFuture;

  @override
  void initState() {
    super.initState();
    _attemptFuture = _fetchAttempt();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _fetchAttempt() {
    return ref
        .read(firestoreProvider)
        .doc(FirestorePaths.examAttempt(widget.companyId, widget.examAttemptId))
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('結果分析')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _attemptFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return ErrorRetryView(
              message: '試験結果の読み込みに失敗しました',
              onRetry: () => setState(() {
                _attemptFuture = _fetchAttempt();
              }),
            );
          }

          final analysis = _ExamAttemptAnalysis.fromMap(snapshot.data!.data()!);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(analysis: analysis),
              const SizedBox(height: 24),
              if (analysis.categories.isNotEmpty) ...[
                const Text(
                  '分野別 正答率',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '正答率70%未満の分野は復習をおすすめします',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                ...analysis.categories.map((c) => _CategoryBar(stat: c)),
                const SizedBox(height: 24),
              ],
              const Text(
                '設問別 正誤',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...analysis.questions.map((q) => _QuestionTile(result: q)),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final _ExamAttemptAnalysis analysis;

  const _SummaryCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: analysis.passed
              ? [Colors.green[700]!, Colors.green[500]!]
              : [Colors.grey[700]!, Colors.grey[500]!],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                analysis.passed ? Icons.check_circle : Icons.cancel,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                analysis.passed ? '合格' : '不合格',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'スコア: ${analysis.score}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '正答数: ${analysis.correctCount} / ${analysis.totalQuestions}問',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (analysis.timeSpentSeconds != null) ...[
            const SizedBox(height: 4),
            Text(
              '所要時間: ${_formatDuration(analysis.timeSpentSeconds!)}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
          if (analysis.autoSubmit) ...[
            const SizedBox(height: 4),
            const Text(
              '※ 制限時間超過または不正防止のため自動提出されました',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m分${s}秒';
  }
}

class _CategoryBar extends StatelessWidget {
  final _CategoryStat stat;

  const _CategoryBar({required this.stat});

  @override
  Widget build(BuildContext context) {
    final isWeak = stat.accuracy < 0.7;
    final color = isWeak ? Colors.orange : Colors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWeak ? Colors.orange.withOpacity(0.08) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: isWeak ? Border.all(color: Colors.orange.withOpacity(0.5)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stat.category,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              if (isWeak)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.warning_amber_rounded,
                      color: Colors.orange[700], size: 18),
                ),
              Text(
                '${(stat.accuracy * 100).round()}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stat.accuracy,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${stat.correct} / ${stat.total}問正解',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  final _QuestionResult result;

  const _QuestionTile({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: result.correct ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.correct ? Icons.check_circle : Icons.cancel,
            color: result.correct ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '問${result.order}　${result.category}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(result.text, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// examAttemptsドキュメントを画面表示用に整形したモデル群。
class _ExamAttemptAnalysis {
  final int score;
  final bool passed;
  final int correctCount;
  final int totalQuestions;
  final int? timeSpentSeconds;
  final bool autoSubmit;
  final List<_CategoryStat> categories; // 正答率が低い順（弱点が上に来る）
  final List<_QuestionResult> questions; // order順

  const _ExamAttemptAnalysis({
    required this.score,
    required this.passed,
    required this.correctCount,
    required this.totalQuestions,
    required this.timeSpentSeconds,
    required this.autoSubmit,
    required this.categories,
    required this.questions,
  });

  factory _ExamAttemptAnalysis.fromMap(Map<String, dynamic> map) {
    final categoryBreakdown =
        (map['categoryBreakdown'] as Map<String, dynamic>?) ?? const {};
    final categories = categoryBreakdown.entries.map((entry) {
      final bucket = entry.value as Map<String, dynamic>? ?? const {};
      final correct = (bucket['correct'] as num?)?.toInt() ?? 0;
      final total = (bucket['total'] as num?)?.toInt() ?? 0;
      return _CategoryStat(
        category: entry.key,
        correct: correct,
        total: total,
        accuracy: total == 0 ? 0 : correct / total,
      );
    }).toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));

    final results = (map['results'] as List<dynamic>?) ?? const [];
    final questions = results
        .map((raw) => _QuestionResult.fromMap(raw as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return _ExamAttemptAnalysis(
      score: (map['score'] as num?)?.toInt() ?? 0,
      passed: map['passed'] as bool? ?? false,
      correctCount: (map['correctCount'] as num?)?.toInt() ?? 0,
      totalQuestions: (map['totalQuestions'] as num?)?.toInt() ?? 0,
      timeSpentSeconds: (map['timeSpentSeconds'] as num?)?.toInt(),
      autoSubmit: map['autoSubmit'] as bool? ?? false,
      categories: categories,
      questions: questions,
    );
  }
}

class _CategoryStat {
  final String category;
  final int correct;
  final int total;
  final double accuracy; // 0.0-1.0

  const _CategoryStat({
    required this.category,
    required this.correct,
    required this.total,
    required this.accuracy,
  });
}

class _QuestionResult {
  final int order;
  final String category;
  final String text;
  final bool correct;

  const _QuestionResult({
    required this.order,
    required this.category,
    required this.text,
    required this.correct,
  });

  factory _QuestionResult.fromMap(Map<String, dynamic> map) {
    return _QuestionResult(
      order: (map['order'] as num?)?.toInt() ?? 0,
      category: map['category'] as String? ?? '未分類',
      text: map['text'] as String? ?? '',
      correct: map['correct'] as bool? ?? false,
    );
  }
}
