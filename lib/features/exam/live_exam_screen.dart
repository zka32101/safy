import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../providers/firebase_providers.dart';
import '../../providers/session_provider.dart';
import '../../services/firestore_paths.dart';
import 'exam_result_analysis_screen.dart';

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

class _LiveExamScreenState extends ConsumerState<LiveExamScreen>
    with WidgetsBindingObserver {
  late Timer _timer;
  late DateTime _startTime;
  late DateTime _endTime;
  int _remainingSeconds = 0;
  int _currentQuestionIndex = 0;
  Map<int, String> _selectedAnswers = {};
  bool _isSubmitting = false;
  bool _examSubmitted = false;
  int? _finalScore;
  String? _examAttemptId;

  List<ExamQuestion> _questions = [];
  bool _questionsLoaded = false;

  // --- 不正防止：バックグラウンド遷移の記録 ---
  int _backgroundCount = 0;
  DateTime? _pausedAt;
  static const int _backgroundWarningThreshold = 2; // これ以降は警告表示
  static const int _backgroundAutoSubmitThreshold = 5; // これ以上で不正防止のため自動提出

  // --- 画面遷移の制限 ---
  // 中断確認ダイアログで「中断する」が選ばれた場合のみtrueにし、
  // その後のpop()でPopScopeが再度ブロックしないようにする。
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTime = DateTime.now();
    _endTime = _startTime.add(Duration(minutes: widget.durationMinutes));
    _remainingSeconds = widget.durationMinutes * 60;
    _loadQuestions();
    _startTimer();
  }

  Future<void> _loadQuestions() async {
    try {
      final snapshot = await ref
          .read(firestoreProvider)
          .collection(FirestorePaths.examQuestions(widget.examId))
          .orderBy('order')
          .get();

      if (!mounted) return;
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
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Timer.periodic の間隔はバックグラウンド時に間引かれることがあるため、
      // カウンタを単純デクリメントせず終了時刻から毎回再計算してズレを防ぐ。
      final remaining = _endTime.difference(DateTime.now()).inSeconds;
      setState(() {
        _remainingSeconds = remaining.clamp(0, widget.durationMinutes * 60);
      });

      if (remaining <= 0) {
        timer.cancel();
        _autoSubmitExam();
      }
    });
  }

  /// アプリのバックグラウンド遷移を検知し、不正防止のための記録・警告・自動提出を行う。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_questionsLoaded || _examSubmitted) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pausedAt ??= DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed && _pausedAt != null) {
      _pausedAt = null;
      _backgroundCount++;

      // 復帰時にも経過時間を実時刻から再計算しておく
      final remaining = _endTime.difference(DateTime.now()).inSeconds;
      if (mounted) {
        setState(() {
          _remainingSeconds = remaining.clamp(0, widget.durationMinutes * 60);
        });
      }

      if (remaining <= 0) {
        _autoSubmitExam();
        return;
      }

      if (_backgroundCount >= _backgroundAutoSubmitThreshold) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('バックグラウンド遷移が規定回数を超えたため、不正防止のため試験を自動提出しました。'),
              duration: Duration(seconds: 5),
            ),
          );
        }
        _autoSubmitExam();
      } else if (_backgroundCount >= _backgroundWarningThreshold &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'アプリがバックグラウンドに移行しました（$_backgroundCount回目）。試験中の離脱は記録されます。',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _autoSubmitExam() async {
    await _submitExam(autoSubmit: true);
  }

  Future<void> _submitExam({bool autoSubmit = false}) async {
    if (_isSubmitting || _examSubmitted) return;

    setState(() => _isSubmitting = true);

    try {
      // SessionState は同期的な単純クラス（StateNotifierProvider）のため、
      // AsyncValue用の .future は存在しない。同期的に読み取って判定する。
      final session = ref.read(sessionProvider);
      if (!session.isSignedIn) {
        throw Exception('セッション情報が取得できません');
      }

      final functions = ref.read(functionsProvider);
      final callable = functions.httpsCallable('submitLiveExam');

      final result = await callable.call({
        'companyId': widget.companyId,
        'employeeId': session.employee!.id,
        'examId': widget.examId,
        'answers': _selectedAnswers,
        'timeSpentSeconds': widget.durationMinutes * 60 - _remainingSeconds,
        'autoSubmit': autoSubmit,
        'backgroundCount': _backgroundCount,
      });

      final score = result.data['score'] as int;
      final passed = result.data['passed'] as bool;
      final examAttemptId = result.data['examAttemptId'] as String?;

      if (!mounted) return;
      setState(() {
        _finalScore = score;
        _examAttemptId = examAttemptId;
        _examSubmitted = true;
        _isSubmitting = false;
      });

      _showResultsDialog(score, passed);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
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
          if (_examAttemptId != null)
            TextButton(
              onPressed: () {
                final attemptId = _examAttemptId!;
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExamResultAnalysisScreen(
                      companyId: widget.companyId,
                      examAttemptId: attemptId,
                    ),
                  ),
                );
              },
              child: const Text('詳細分析を見る'),
            ),
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
    WidgetsBinding.instance.removeObserver(this);
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
              const SizedBox(height: 24),
              if (_examAttemptId != null)
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ExamResultAnalysisScreen(
                          companyId: widget.companyId,
                          examAttemptId: _examAttemptId!,
                        ),
                      ),
                    );
                  },
                  child: const Text('詳細分析を見る'),
                ),
              const SizedBox(height: 12),
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

    return PopScope(
      // 試験進行中は誤操作・不正離脱防止のため、確認なしの画面離脱を禁止する
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('試験を中断しますか？'),
                content: const Text(
                  '試験を中断すると、ここまでの回答は保存されません。本当に中断しますか？',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('続ける'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('中断する'),
                  ),
                ],
              ),
            ) ??
            false;
        if (shouldLeave && mounted) {
          // canPopをtrueにしてから改めてpop()することで、PopScopeに
          // 再度ブロックされることなく確実に画面を離脱できるようにする。
          setState(() => _allowPop = true);
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
              '${widget.examId} - 問題 ${_currentQuestionIndex + 1}/${_questions.length}'),
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
  final String category; // 分野別分析用（未設定の問題は「未分類」扱い）
  final String text;
  final List<String> options; // A, B, C, D
  final int correctOption; // 0-3

  ExamQuestion({
    required this.id,
    required this.order,
    required this.category,
    required this.text,
    required this.options,
    required this.correctOption,
  });

  factory ExamQuestion.fromMap(Map<String, dynamic> map) {
    return ExamQuestion(
      id: map['id'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      category: map['category'] as String? ?? '未分類',
      text: map['text'] as String? ?? '',
      options: List<String>.from(map['options'] as List? ?? []),
      correctOption: (map['correctOption'] as num?)?.toInt() ?? 0,
    );
  }
}
