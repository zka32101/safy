import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../widgets/error_retry_view.dart';

/// Q&A フォーラム質問詳細画面
class QuestionDetailScreen extends StatefulWidget {
  final String questionId;
  final String companyId;

  const QuestionDetailScreen({
    super.key,
    required this.questionId,
    required this.companyId,
  });

  @override
  State<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends State<QuestionDetailScreen> {
  late Future<Map<String, dynamic>> _questionFuture;
  final _answerController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _questionFuture = _loadQuestion();
  }

  Future<Map<String, dynamic>> _loadQuestion() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(widget.companyId)
          .collection('qaForum')
          .doc(widget.questionId)
          .get();

      if (!doc.exists) {
        return {'error': '質問が見つかりません'};
      }

      // ビュー数をインクリメント
      await doc.reference.update({
        'viewCount': FieldValue.increment(1),
      });

      return {'id': widget.questionId, ...doc.data() as Map<String, dynamic>};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> _submitAnswer(String questionData) async {
    if (_answerController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('回答を入力してください')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('submitAnswer');

      await callable.call({
        'companyId': widget.companyId,
        'questionId': widget.questionId,
        'content': _answerController.text,
      });

      _answerController.clear();
      setState(() {
        _isSubmitting = false;
        _questionFuture = _loadQuestion();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回答を投稿しました')),
        );
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('投稿に失敗しました')),
        );
      }
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('質問詳細'),
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _questionFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data?['error'] != null) {
            return ErrorRetryView(
              message: snapshot.data?['error']?.toString() ?? 'エラーが発生しました',
              onRetry: () => setState(() {
                _questionFuture = _loadQuestion();
              }),
            );
          }

          final question = snapshot.data ?? {};

          return SingleChildScrollView(
            child: Column(
              children: [
                _buildQuestionSection(question),
                _buildAnswersSection(question),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildAnswerInput(context),
    );
  }

  Widget _buildQuestionSection(Map<String, dynamic> question) {
    final title = question['title'] as String? ?? '';
    final description = question['description'] as String? ?? '';
    final category = question['category'] as String? ?? '';
    final authorName = question['authorName'] as String? ?? '';
    final createdAt = question['createdAt'] as Timestamp?;
    final answerCount = question['answerCount'] as int? ?? 0;
    final viewCount = question['viewCount'] as int? ?? 0;

    String timeAgo = '';
    if (createdAt != null) {
      final now = DateTime.now();
      final created = createdAt.toDate();
      final diff = now.difference(created);

      if (diff.inHours < 1) {
        timeAgo = '${diff.inMinutes}分前';
      } else if (diff.inDays < 1) {
        timeAgo = '${diff.inHours}時間前';
      } else {
        timeAgo = '${diff.inDays}日前';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (description.isNotEmpty)
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (category.isNotEmpty)
                Chip(
                  label: Text(category),
                  backgroundColor: Colors.green.withOpacity(0.1),
                  labelStyle: TextStyle(
                    color: Colors.green[700],
                    fontSize: 12,
                  ),
                ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                authorName,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeAgo,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
              const Spacer(),
              Icon(Icons.comment_outlined, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                answerCount.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.visibility_outlined, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                viewCount.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnswersSection(Map<String, dynamic> question) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('companies')
            .doc(widget.companyId)
            .collection('qaForum')
            .doc(widget.questionId)
            .collection('answers')
            .where('status', isEqualTo: 'active')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final answers = snapshot.data?.docs ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '回答 (${answers.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (answers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  child: Text(
                    'まだ回答がありません。最初の回答者になってください！',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                )
              else
                ...answers.map((doc) {
                  final answer = doc.data() as Map<String, dynamic>;
                  final content = answer['content'] as String? ?? '';
                  final authorName = answer['authorName'] as String? ?? '';
                  final createdAt = answer['createdAt'] as Timestamp?;
                  final likes = answer['likes'] as int? ?? 0;

                  String timeAgo = '';
                  if (createdAt != null) {
                    final now = DateTime.now();
                    final created = createdAt.toDate();
                    final diff = now.difference(created);

                    if (diff.inHours < 1) {
                      timeAgo = '${diff.inMinutes}分前';
                    } else if (diff.inDays < 1) {
                      timeAgo = '${diff.inHours}時間前';
                    } else {
                      timeAgo = '${diff.inDays}日前';
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            content,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                authorName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                timeAgo,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                              const Spacer(),
                              Icon(Icons.favorite_outline,
                                  size: 16, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text(
                                likes.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnswerInput(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
        color: Colors.white,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _answerController,
            enabled: !_isSubmitting,
            maxLines: null,
            decoration: InputDecoration(
              hintText: '回答を入力...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isSubmitting ? null : () => _answerController.clear(),
                child: const Text('クリア'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSubmitting ? null : () => _submitAnswer(''),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('投稿'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
