import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../providers/session_provider.dart';

/// レベル診断画面：従業員のスキルレベルを判定して学習パス推奨
class LevelDiagnosticScreen extends ConsumerStatefulWidget {
  const LevelDiagnosticScreen({super.key});

  @override
  ConsumerState<LevelDiagnosticScreen> createState() =>
      _LevelDiagnosticScreenState();
}

class _LevelDiagnosticScreenState extends ConsumerState<LevelDiagnosticScreen> {
  int _currentQuestionIndex = 0;
  Map<int, int> _answers = {};
  bool _isSubmitting = false;
  int? _diagnosticScore;
  String? _recommendedLevel; // beginner, intermediate, advanced

  final diagnosticQuestions = [
    {
      'question': 'あなたの現在の業務経験は？',
      'options': [
        '0-1年（新入社員・未経験）',
        '1-3年（基礎的な知識あり）',
        '3-5年（実務経験豊富）',
        '5年以上（リーダー・専門家水準）',
      ],
    },
    {
      'question': 'デジタルツールの使用経験は？',
      'options': [
        'ほぼ未経験',
        '基本的なツール（Excel等）のみ',
        '複数のツール・プラットフォーム使用経験あり',
        'クラウド・データ分析ツール等を日常的に使用',
      ],
    },
    {
      'question': 'チームでの役割は？',
      'options': [
        '個人業務中心',
        'チームメンバー（平社員）',
        'チームリーダー・マネージャー',
        '部門長・経営層',
      ],
    },
    {
      'question': 'データ・分析スキルの自己評価は？',
      'options': [
        'データの扱いに不安がある',
        '基本的な集計・レポート作成ができる',
        'データ分析・可視化ができる',
        'ビジネス分析・戦略立案に活用できる',
      ],
    },
    {
      'question': 'コミュニケーション・プレゼンスキルは？',
      'options': [
        'グループでのスピーチは得意でない',
        '一対一・小グループでの説明はできる',
        '会議・プレゼンテーションで要点を述べられる',
        '大勢の前での説得的なプレゼンが得意',
      ],
    },
  ];

  Future<void> _submitDiagnostic() async {
    setState(() => _isSubmitting = true);

    try {
      final session = ref.read(sessionProvider);
      if (!session.isSignedIn) {
        throw Exception('セッション情報が取得できません');
      }

      // スコア計算：回答を集計
      int totalScore = 0;
      for (int i = 0; i < diagnosticQuestions.length; i++) {
        totalScore += _answers[i] ?? 0;
      }

      final averageScore = totalScore / diagnosticQuestions.length;
      final recommendedLevel = _determineLevel(averageScore);

      // Cloud Functions で診断結果を保存
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('completeLevelDiagnostic');

      await callable.call({
        'companyId': session.employee!.companyId,
        'employeeId': session.employee!.id,
        'answers': _answers,
        'totalScore': totalScore,
        'averageScore': averageScore,
        'recommendedLevel': recommendedLevel,
      });

      setState(() {
        _diagnosticScore = totalScore;
        _recommendedLevel = recommendedLevel;
        _isSubmitting = false;
      });

      if (mounted) {
        _showResultsDialog();
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('診断に失敗しました: $e')),
        );
      }
    }
  }

  String _determineLevel(double averageScore) {
    if (averageScore < 1.5) return 'beginner';
    if (averageScore < 2.5) return 'intermediate';
    return 'advanced';
  }

  void _showResultsDialog() {
    final levelLabels = {
      'beginner': '初級者向け',
      'intermediate': '中級者向け',
      'advanced': '上級者向け',
    };

    final levelDescriptions = {
      'beginner': '基礎スキル強化・ツール習得を優先した学習パスをお勧めします',
      'intermediate': '実践的なスキル・リーダーシップスキルの強化をお勧めします',
      'advanced': '戦略的思考・マネジメント・業界トレンドの深掘りをお勧めします',
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('診断完了'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'あなたのレベル：',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: Text(
                levelLabels[_recommendedLevel] ?? '',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              levelDescriptions[_recommendedLevel] ?? '',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('学習パスを見る'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_diagnosticScore != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('診断完了')),
        body: const Center(
          child: Text('診断が完了しました'),
        ),
      );
    }

    final question = diagnosticQuestions[_currentQuestionIndex];
    final selectedAnswer = _answers[_currentQuestionIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text('スキルレベル診断 (${_currentQuestionIndex + 1}/${diagnosticQuestions.length})'),
        elevation: 0,
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentQuestionIndex + 1) / diagnosticQuestions.length,
            minHeight: 8,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question['question'] as String,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...(question['options'] as List<String>).asMap().entries.map((entry) {
                    final index = entry.key;
                    final option = entry.value;
                    final isSelected = selectedAnswer == index;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _answers[_currentQuestionIndex] = index;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.withOpacity(0.2)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? Colors.blue : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.blue : Colors.grey,
                                    ),
                                    color: isSelected ? Colors.blue : Colors.transparent,
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    option,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                if (_currentQuestionIndex > 0)
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _currentQuestionIndex--);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[400],
                    ),
                    child: const Text('前へ'),
                  )
                else
                  const SizedBox(width: 80),
                const Spacer(),
                if (_currentQuestionIndex < diagnosticQuestions.length - 1)
                  ElevatedButton(
                    onPressed: _answers.containsKey(_currentQuestionIndex)
                        ? () {
                            setState(() => _currentQuestionIndex++);
                          }
                        : null,
                    child: const Text('次へ'),
                  )
                else
                  ElevatedButton(
                    onPressed: _isSubmitting ||
                            !_answers.containsKey(_currentQuestionIndex)
                        ? null
                        : _submitDiagnostic,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('診断を完了'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
