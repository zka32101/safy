import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import '../../providers/session_provider.dart';
import '../../widgets/error_retry_view.dart';

/// ライブ認定試験画面：Tier 2/3 試験（90/120分）
class LiveExamScreen extends ConsumerStatefulWidget {
  final String examId; // tier2-exam or tier3-exam
  final String companyId;
  final int durationMinutes; // 90 or 120

  const LiveExamScreen({
    super.key,
    required this.examId,
    required this.companyId,
    this.durationMinutes = 90,
  });

  @override
  ConsumerState<LiveExamScreen> createState() => _LiveExamScreenState();
}

class _LiveExamScreenState extends ConsumerState<LiveExamScreen> {
  late Timer _timer;
  late DateTime _startTime;
  late DateTime _endTime;
  int _remainingSeconds = 0;
  int _currentQuestionIndex = 0;
  Map<int, String> _selectedAnswers = {};
  bool _isSubmitting = false;
  bool _examSubmitted = false;
  int? _finalScore;

  List<ExamQuestion> _questions = [];
  bool _questionsLoaded = false;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _endTime = _startTime.add(Duration(minutes: widget.durationMinutes));
    _remainingSeconds = widget.durationMinutes * 60;
    _loadQuestions();
    _startTimer();
  }

  Future<void> _loadQuestions() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('exams')
          .doc(widget.examId)
          .collection('questions')
          .orderBy('order')
          .get();

      setState(() {
        _questions = snapshot.docs
            .map((doc) => ExamQuestion.fromMap(doc.data()))
            .toList();
        _questionsLoaded = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('問題の読み込みに失敗しました: $e')),
        );
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingSeconds--;
      });

      if (_remainingSeconds <= 0) {
        timer.cancel();
        _autoSubmitExam();
      }
    });
  }

  Future<void> _autoSubmitExam() async {
    await _submitExam(autoSubmit: true);
  }

  Future<void> _submitExam({bool autoSubmit = false}) async {
    if (_isSubmitting || _examSubmitted) return;

    setState(() => _isSubmitting = true);

    try {
      final session = await ref.read(sessionProvider.future);
      if (session == null) {
        throw Exception('セッション情報が取得できません');
      }

      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('submitLiveExam');

      final result = await callable.call({
        'companyId': widget.companyId,
        'employeeId': session.userId,
        'examId': widget.examId,
        'answers': _selectedAnswers,
        'timeSpentSeconds': widget.durationMinutes * 60 - _remainingSeconds,
        'autoSubmit': autoSubmit,
      });

      final score = result.data['score'] as int;
      final passed = result.data['passed'] as bool;

      setState(() {
        _finalScore = score;
        _examSubmitted = true;
        _isSubmitting = false;
      });

      if (mounted) {
        _showResultsDialog(score, passed);
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('試験の提出に失敗しました: $e')),
        );
      }
    }
  }

  void _showResultsDialog(int score, bool passed) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('試験完了'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              passed ? Icons.check_circle : Icons.cancel,
              size: 64,
              color: passed ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'スコア: $score%',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              passed ? '合格おめでとうございます！' : '残念ながら不合格です。再受験してください。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: passed ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('戻る'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_questionsLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('試験読み込み中...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_examSubmitted) {
      return Scaffold(
        appBar: AppBar(title: const Text('試験完了')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle,
                size: 80,
                color: Colors.green,
              ),
              const SizedBox(height: 24),
              Text(
                'スコア: $_finalScore%',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('戻る'),
              ),
            ],
          ),
        ),
      );
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final isTimeWarning = _remainingSeconds < 300; // 5分以下で警告

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.examId} - 問題 ${_currentQuestionIndex + 1}/${_questions.length}'),
        elevation: 0,
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Center(
              child: Text(
                '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isTimeWarning ? Colors.red : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: (_currentQuestionIndex + 1) / _questions.length,
            minHeight: 8,
          ),
          // Question
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentQuestion.text,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ..._buildAnswerOptions(currentQuestion),
                ],
              ),
            ),
          ),
          // Navigation buttons
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
                if (_currentQuestionIndex < _questions.length - 1)
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _currentQuestionIndex++);
                    },
                    child: const Text('次へ'),
                  )
                else
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitExam,
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
                        : const Text('提出'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAnswerOptions(ExamQuestion question) {
    return question.options.asMap().entries.map((entry) {
      final index = entry.key;
      final option = entry.value;
      final optionKey = 'option_${index}a';
      final isSelected = _selectedAnswers[_currentQuestionIndex] == optionKey;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedAnswers[_currentQuestionIndex] = optionKey;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.grey[100],
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
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      option,
                      style: const TextStyle(fontSize: 16),
                    ),
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

class ExamQuestion {
  final String id;
  final int order;
  final String text;
  final List<String> options; // A, B, C, D
  final int correctOption; // 0-3

  ExamQuestion({
    required this.id,
    required this.order,
    required this.text,
    required this.options,
    required this.correctOption,
  });

  factory ExamQuestion.fromMap(Map<String, dynamic> map) {
    return ExamQuestion(
      id: map['id'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      text: map['text'] as String? ?? '',
      options: List<String>.from(map['options'] as List? ?? []),
      correctOption: (map['correctOption'] as num?)?.toInt() ?? 0,
    );
  }
}
