import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/session_provider.dart';
import 'live_exam_screen.dart';

/// 試験選択・受験画面：Tier 2/3 試験の申し込みと受験開始
class ExamEnrollmentScreen extends ConsumerWidget {
  const ExamEnrollmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // SessionState は StateNotifierProvider が保持する同期的な単純クラスのため、
    // AsyncValue 用の .when()/.future/.valueOrNull は使わず isSignedIn で判定する。
    final session = ref.watch(sessionProvider);

    if (!session.isSignedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('認定試験')),
        body: const Center(
          child: Text('ログインが必要です'),
        ),
      );
    }

    return _ExamSelectionContent(
      companyId: session.employee!.companyId,
      employeeId: session.employee!.id,
    );
  }
}

class _ExamSelectionContent extends StatelessWidget {
  final String companyId;
  final String employeeId;

  const _ExamSelectionContent({
    required this.companyId,
    required this.employeeId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('認定試験'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.indigo[700]!,
                    Colors.indigo[500]!,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ライブ認定試験',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tier 1 Training 修了後、Tier 2/3 試験に挑戦できます',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Oct 10-20 実施',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Exam cards
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '実施予定試験',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildExamCard(
                    context,
                    title: 'Tier 2 認定試験',
                    description: '実務応用スキルの検定試験',
                    duration: 90,
                    examId: 'tier2-exam',
                    color: Colors.blue,
                    icon: Icons.school,
                  ),
                  const SizedBox(height: 12),
                  _buildExamCard(
                    context,
                    title: 'Tier 3 認定試験',
                    description: '高度な応用・戦略的思考',
                    duration: 120,
                    examId: 'tier3-exam',
                    color: Colors.purple,
                    icon: Icons.star,
                  ),
                ],
              ),
            ),

            // Information section
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info, color: Colors.amber),
                      SizedBox(width: 8),
                      Text(
                        '試験受験について',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '・受験するには Tier 1 Training 全モジュール修了が必須です\n'
                    '・一度開始した試験は制限時間内に必ず提出してください\n'
                    '・不合格の場合は何度でも再受験できます\n'
                    '・各試験の合格ラインは 70% です',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamCard(
    BuildContext context, {
    required String title,
    required String description,
    required int duration,
    required String examId,
    required Color color,
    required IconData icon,
  }) {
    return Material(
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LiveExamScreen(
                examId: examId,
                companyId: companyId,
                durationMinutes: duration,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: color),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '制限時間: $duration分',
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
