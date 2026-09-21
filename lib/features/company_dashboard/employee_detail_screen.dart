import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../providers/firebase_providers.dart';
import '../../widgets/error_retry_view.dart';

/// 従業員の研修詳細画面：各モジュール別の進捗・スコア・再試行履歴を表示
class EmployeeDetailScreen extends ConsumerWidget {
  final String companyId;
  final String employeeId;
  final String? employeeName;

  const EmployeeDetailScreen({
    super.key,
    required this.companyId,
    required this.employeeId,
    this.employeeName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firestore = ref.watch(firestoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('従業員詳細: ${employeeName ?? employeeId}'),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection('companies')
            .doc(companyId)
            .collection('trainingAttempts')
            .where('employeeId', isEqualTo: employeeId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ErrorRetryView(
              message: '受講記録の読み込みに失敗しました: ${snapshot.error}',
              onRetry: () {},
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final moduleMap = _groupByModule(docs);

          return SingleChildScrollView(
            child: Column(
              children: [
                _buildOverallProgress(context, docs),
                const SizedBox(height: 24),
                _buildModuleDetails(context, moduleMap),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverallProgress(BuildContext context, List<QueryDocumentSnapshot> docs) {
    final modules = [
      'tier1-platform-tech',
      'tier1-operations',
      'tier1-content-production',
      'tier1-gtm-strategy',
    ];

    final completedModules = modules
        .where((module) =>
            docs.any((doc) =>
                (doc.data() as Map)['moduleId'] == module &&
                (doc.data() as Map)['passed'] == true))
        .length;

    final completionPercent = (completedModules / 4 * 100).toInt();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '全体進捗',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '修了状況',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$completedModules/4',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: completedModules == 4 ? Colors.green : Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: completionPercent / 100,
                    minHeight: 12,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      completedModules == 4 ? Colors.green : Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$completionPercent%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<QueryDocumentSnapshot>> _groupByModule(
    List<QueryDocumentSnapshot> docs,
  ) {
    final map = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in docs) {
      final moduleId = (doc.data() as Map)['moduleId'] as String;
      map.putIfAbsent(moduleId, () => []).add(doc);
    }
    return map;
  }

  Widget _buildModuleDetails(
    BuildContext context,
    Map<String, List<QueryDocumentSnapshot>> moduleMap,
  ) {
    final moduleNames = {
      'tier1-platform-tech': 'Platform技術',
      'tier1-operations': 'Operations',
      'tier1-content-production': 'Content Production',
      'tier1-gtm-strategy': 'GTM Strategy',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'モジュール別詳細',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...moduleNames.entries.map((entry) {
            final moduleId = entry.key;
            final moduleName = entry.value;
            final attempts = moduleMap[moduleId] ?? [];

            if (attempts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildModuleCard(
                  context,
                  moduleName: moduleName,
                  attempts: [],
                  status: 'not_started',
                ),
              );
            }

            final isPassed =
                attempts.any((doc) => (doc.data() as Map)['passed'] == true);
            final scores = attempts
                .map((doc) => (doc.data() as Map)['score'] as int? ?? 0)
                .toList();
            final maxScore = scores.isNotEmpty ? scores.reduce((a, b) => a > b ? a : b) : 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildModuleCard(
                context,
                moduleName: moduleName,
                attempts: attempts,
                status: isPassed ? 'passed' : 'incomplete',
                maxScore: maxScore,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildModuleCard(
    BuildContext context, {
    required String moduleName,
    required List<QueryDocumentSnapshot> attempts,
    required String status,
    int maxScore = 0,
  }) {
    final backgroundColor = status == 'passed'
        ? Colors.green.withOpacity(0.1)
        : status == 'not_started'
            ? Colors.grey.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1);

    final borderColor =
        status == 'passed' ? Colors.green : status == 'not_started' ? Colors.grey : Colors.orange;

    final statusText = status == 'passed'
        ? '修了'
        : status == 'not_started'
            ? '未開始'
            : '進行中';

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            moduleName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            attempts.isEmpty
                                ? '未開始'
                                : '${attempts.length}回チャレンジ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: borderColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: borderColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (attempts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '最高スコア',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            '$maxScore%',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: maxScore >= 80 ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      if (status == 'passed')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle, size: 16, color: Colors.green),
                              SizedBox(width: 4),
                              Text(
                                '合格',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (attempts.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Column(
                children: attempts.asMap().entries.map((entry) {
                  final index = entry.key;
                  final doc = entry.value;
                  final data = doc.data() as Map<String, dynamic>;
                  final score = data['score'] as int? ?? 0;
                  final timestamp = data['createdAt'] as dynamic?;
                  final dateStr = timestamp != null
                      ? _formatDate(timestamp)
                      : '日付不明';

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '試行 ${index + 1}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$score%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: score >= 80 ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    try {
      DateTime dateTime;
      if (timestamp is String) {
        dateTime = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        dateTime = timestamp;
      } else if (timestamp.runtimeType.toString().contains('Timestamp')) {
        dateTime = (timestamp as dynamic).toDate();
      } else {
        return '日付不明';
      }
      return DateFormat('yyyy/MM/dd HH:mm').format(dateTime);
    } catch (e) {
      return '日付不明';
    }
  }
}
