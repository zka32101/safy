import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../providers/session_provider.dart';
import '../../widgets/error_retry_view.dart';
import 'question_detail_screen.dart';

/// Q&A フォーラム画面：従業員間の質問・回答
class QAForumScreen extends ConsumerStatefulWidget {
  const QAForumScreen({super.key});

  @override
  ConsumerState<QAForumScreen> createState() => _QAForumScreenState();
}

class _QAForumScreenState extends ConsumerState<QAForumScreen> {
  String _sortBy = 'recent'; // recent, popular, unanswered
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return session.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Q&Aフォーラム')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => Scaffold(
        appBar: AppBar(title: const Text('Q&Aフォーラム')),
        body: ErrorRetryView(
          error: err.toString(),
          onRetry: () => ref.refresh(sessionProvider),
        ),
      ),
      data: (sessionData) {
        if (sessionData == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Q&Aフォーラム')),
            body: const Center(child: Text('ログインが必要です')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Q&Aフォーラム'),
            elevation: 0,
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                      decoration: InputDecoration(
                        hintText: '質問を検索...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildSortChip('recent', '最新', Icons.access_time),
                                const SizedBox(width: 8),
                                _buildSortChip('popular', '人気', Icons.trending_up),
                                const SizedBox(width: 8),
                                _buildSortChip('unanswered', '未回答', Icons.help_outline),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildQuestionsList(
                  context,
                  sessionData.companyId,
                  sessionData.userId,
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAskQuestionDialog(context, sessionData),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildSortChip(String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    return FilterChip(
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _sortBy = selected ? value : _sortBy);
      },
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      backgroundColor: isSelected ? Colors.blue.withOpacity(0.2) : Colors.grey[200],
      selectedColor: Colors.blue.withOpacity(0.3),
    );
  }

  Widget _buildQuestionsList(
    BuildContext context,
    String companyId,
    String employeeId,
  ) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('companies')
        .doc(companyId)
        .collection('qaForum')
        .where('status', isEqualTo: 'active');

    if (_searchQuery.isNotEmpty) {
      query = query.where('title', isGreaterThanOrEqualTo: _searchQuery)
          .where('title', isLessThan: _searchQuery + 'z');
    }

    if (_sortBy == 'recent') {
      query = query.orderBy('createdAt', descending: true);
    } else if (_sortBy == 'popular') {
      query = query.orderBy('viewCount', descending: true);
    } else if (_sortBy == 'unanswered') {
      query = query.where('answerCount', isEqualTo: 0)
          .orderBy('createdAt', descending: true);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.limit(50).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return ErrorRetryView(
            error: snapshot.error.toString(),
            onRetry: () => setState(() {}),
          );
        }

        final questions = snapshot.data?.docs ?? [];

        if (questions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.help_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  '質問がまだありません',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: questions.length,
          itemBuilder: (context, index) {
            final doc = questions[index];
            final question = doc.data() as Map<String, dynamic>;

            return _buildQuestionCard(context, question, doc.id, employeeId);
          },
        );
      },
    );
  }

  Widget _buildQuestionCard(
    BuildContext context,
    Map<String, dynamic> question,
    String questionId,
    String employeeId,
  ) {
    final title = question['title'] as String? ?? '';
    final description = question['description'] as String? ?? '';
    final authorName = question['authorName'] as String? ?? '匿名';
    final answerCount = question['answerCount'] as int? ?? 0;
    final viewCount = question['viewCount'] as int? ?? 0;
    final category = question['category'] as String? ?? '';
    final createdAt = question['createdAt'] as Timestamp?;
    final isMine = question['authorId'] as String? == employeeId;

    String timeAgo = '';
    if (createdAt != null) {
      final now = DateTime.now();
      final created = createdAt.toDate();
      final diff = now.difference(created);

      if (diff.inHours < 1) {
        timeAgo = '${diff.inMinutes}分前';
      } else if (diff.inDays < 1) {
        timeAgo = '${diff.inHours}時間前';
      } else if (diff.inDays < 30) {
        timeAgo = '${diff.inDays}日前';
      } else {
        timeAgo = created.toLocal().toString().split(' ')[0];
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => QuestionDetailScreen(
                  questionId: questionId,
                  companyId: question['companyId'] as String? ?? '',
                ),
              ),
            );
          },
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isMine)
                                Chip(
                                  label: const Text('自分'),
                                  backgroundColor: Colors.blue.withOpacity(0.2),
                                  labelStyle: TextStyle(
                                    color: Colors.blue[700],
                                    fontSize: 11,
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (category.isNotEmpty)
                      Chip(
                        label: Text(category),
                        backgroundColor: Colors.green.withOpacity(0.1),
                        labelStyle: TextStyle(
                          color: Colors.green[700],
                          fontSize: 11,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 8),
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
          ),
        ),
      ),
    );
  }

  void _showAskQuestionDialog(BuildContext context, dynamic sessionData) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String category = 'その他';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('質問を投稿'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  enabled: !isSubmitting,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: 'タイトル*',
                    hintText: '質問のタイトルを入力',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  maxLines: null,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  enabled: !isSubmitting,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: '詳細',
                    hintText: '詳しく説明してください（オプション）',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: category,
                  onChanged: isSubmitting
                      ? null
                      : (value) {
                          setState(() => category = value ?? 'その他');
                        },
                  decoration: InputDecoration(
                    labelText: 'カテゴリ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: [
                    'コンテンツ理解',
                    'スキル応用',
                    'ツール・システム',
                    'キャリア',
                    'その他',
                  ].map((cat) => DropdownMenuItem(
                    value: cat,
                    child: Text(cat),
                  )).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () {
                      if (titleController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('タイトルを入力してください')),
                        );
                        return;
                      }
                      _submitQuestion(
                        context,
                        sessionData.companyId,
                        sessionData.userId,
                        titleController.text,
                        descriptionController.text,
                        category,
                        setState,
                      );
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('投稿'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitQuestion(
    BuildContext context,
    String companyId,
    String employeeId,
    String title,
    String description,
    String category,
    StateSetter setState,
  ) async {
    setState(() {});

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('submitQuestion');

      await callable.call({
        'companyId': companyId,
        'employeeId': employeeId,
        'title': title,
        'description': description,
        'category': category,
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('質問を投稿しました')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('投稿に失敗しました')),
        );
      }
    }
  }
}
