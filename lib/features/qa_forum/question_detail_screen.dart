import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/session_provider.dart';
import '../../providers/firebase_providers.dart';
import '../../services/firestore_paths.dart';
import '../../widgets/error_retry_view.dart';

/// Q&A フォーラム質問詳細画面
class QuestionDetailScreen extends ConsumerStatefulWidget {
  final String questionId;
  final String companyId;

  const QuestionDetailScreen({
    super.key,
    required this.questionId,
    required this.companyId,
  });

  @override
  ConsumerState<QuestionDetailScreen> createState() =>
      _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends ConsumerState<QuestionDetailScreen> {
  final _answerController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // ビュー数をインクリメント（失敗しても画面表示には影響させない）
    _incrementViewCount();
  }

  Future<void> _incrementViewCount() async {
    try {
      final firestore = ref.read(firestoreProvider);
      await firestore
          .doc(FirestorePaths.qaQuestion(widget.companyId, widget.questionId))
          .update({
        'viewCount': FieldValue.increment(1),
      });
    } catch (_) {
      // 閲覧数の更新に失敗しても致命的ではないため無視する
    }
  }

  Future<void> _submitAnswer() async {
    if (_answerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('回答を入力してください')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final functions = ref.read(functionsProvider);
      final callable = functions.httpsCallable('submitAnswer');

      await callable.call({
        'companyId': widget.companyId,
        'questionId': widget.questionId,
        'content': _answerController.text,
      });

      _answerController.clear();

      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回答を投稿しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('投稿に失敗しました')),
        );
      }
    }
  }

  Future<void> _toggleBestAnswer(String answerId, bool isCurrentlyBest) async {
    try {
      final functions = ref.read(functionsProvider);
      await functions.httpsCallable('setBestAnswer').call({
        'companyId': widget.companyId,
        'questionId': widget.questionId,
        'answerId': answerId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCurrentlyBest ? 'ベストアンサーを解除しました' : 'ベストアンサーに選択しました',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ベストアンサーの設定に失敗しました')),
        );
      }
    }
  }

  Future<void> _toggleHelpful(String answerId) async {
    try {
      final functions = ref.read(functionsProvider);
      await functions.httpsCallable('toggleAnswerHelpful').call({
        'companyId': widget.companyId,
        'questionId': widget.questionId,
        'answerId': answerId,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('リアクションの送信に失敗しました')),
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
    final session = ref.watch(sessionProvider);
    final firestore = ref.watch(firestoreProvider);
    final currentEmployeeId = session.employee?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('質問詳細'),
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: firestore
            .doc(FirestorePaths.qaQuestion(widget.companyId, widget.questionId))
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ErrorRetryView(
              message: snapshot.error.toString(),
              onRetry: () => setState(() {}),
            );
          }

          final doc = snapshot.data;
          if (doc == null || !doc.exists) {
            return const ErrorRetryView(message: '質問が見つかりません');
          }

          final question = {'id': doc.id, ...doc.data()!};
          final isQuestionAuthor = currentEmployeeId != null &&
              (question['authorId'] as String?) == currentEmployeeId;

          return SingleChildScrollView(
            child: Column(
              children: [
                _buildQuestionSection(question),
                _buildAnswersSection(
                  firestore,
                  currentEmployeeId,
                  isQuestionAuthor,
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildAnswerInput(session),
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

  Widget _buildAnswersSection(
    FirebaseFirestore firestore,
    String? currentEmployeeId,
    bool isQuestionAuthor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firestore
            .collection(
                FirestorePaths.qaAnswers(widget.companyId, widget.questionId))
            .where('status', isEqualTo: 'active')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final answers = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            snapshot.data?.docs ?? [],
          );

          // ベストアンサーを先頭に表示する
          answers.sort((a, b) {
            final aIsBest = (a.data()['isBestAnswer'] as bool?) ?? false;
            final bIsBest = (b.data()['isBestAnswer'] as bool?) ?? false;
            if (aIsBest == bIsBest) return 0;
            return aIsBest ? -1 : 1;
          });

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
                ...answers.map((doc) => _buildAnswerCard(
                      doc,
                      currentEmployeeId,
                      isQuestionAuthor,
                    )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnswerCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String? currentEmployeeId,
    bool isQuestionAuthor,
  ) {
    final answer = doc.data();
    final answerId = doc.id;
    final content = answer['content'] as String? ?? '';
    final authorName = answer['authorName'] as String? ?? '';
    final createdAt = answer['createdAt'] as Timestamp?;
    final likes = answer['likes'] as int? ?? 0;
    final isBestAnswer = (answer['isBestAnswer'] as bool?) ?? false;
    final helpfulEmployeeIds =
        (answer['helpfulEmployeeIds'] as List?)?.cast<String>() ?? const [];
    final hasReacted = currentEmployeeId != null &&
        helpfulEmployeeIds.contains(currentEmployeeId);

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
          color: isBestAnswer ? Colors.amber.withOpacity(0.12) : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isBestAnswer ? Colors.amber[700]! : Colors.grey[300]!,
            width: isBestAnswer ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isBestAnswer)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events, size: 18, color: Colors.amber[800]),
                    const SizedBox(width: 4),
                    Text(
                      'ベストアンサー',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber[800],
                      ),
                    ),
                  ],
                ),
              ),
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
                if (isQuestionAuthor)
                  TextButton.icon(
                    onPressed: () => _toggleBestAnswer(answerId, isBestAnswer),
                    icon: Icon(
                      isBestAnswer
                          ? Icons.emoji_events
                          : Icons.emoji_events_outlined,
                      size: 16,
                      color: isBestAnswer ? Colors.amber[800] : Colors.grey[600],
                    ),
                    label: Text(
                      isBestAnswer ? '選択解除' : 'ベストアンサーに選択',
                      style: TextStyle(
                        fontSize: 12,
                        color: isBestAnswer ? Colors.amber[800] : Colors.grey[600],
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: currentEmployeeId == null
                      ? null
                      : () => _toggleHelpful(answerId),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasReacted ? Icons.favorite : Icons.favorite_outline,
                          size: 16,
                          color: hasReacted ? Colors.red[400] : Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          likes.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            color: hasReacted ? Colors.red[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerInput(SessionState session) {
    if (!session.isSignedIn) {
      return const SizedBox.shrink();
    }

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
                onPressed: _isSubmitting ? null : _submitAnswer,
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
