import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/models/module_model.dart';
import '../../data/models/enrollment_model.dart';
import '../../providers/service_providers.dart';
import '../../providers/session_provider.dart';
import '../lesson/lesson_screen.dart';
import '../../widgets/error_retry_view.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/empty_state_view.dart';

/// Tier 1 Training Dashboard: Sep 16-22 自習期間の学習進捗管理画面
class TrainingDashboardScreen extends ConsumerStatefulWidget {
  const TrainingDashboardScreen({super.key});

  @override
  ConsumerState<TrainingDashboardScreen> createState() =>
      _TrainingDashboardScreenState();
}

class _TrainingDashboardScreenState
    extends ConsumerState<TrainingDashboardScreen> {
  static const String _trainingPeriodStart = '2026-09-16';
  static const String _trainingPeriodEnd = '2026-09-22';
  static const String _trainingDeadline = '2026-09-22T23:59:59+09:00';

  // Tier 1 Training module IDs
  static const List<String> tierOneModuleIds = [
    'tier1-platform-tech',
    'tier1-operations',
    'tier1-content-production',
    'tier1-gtm-strategy',
  ];

  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tier 1 研修'),
        elevation: 0,
      ),
      body: Consumer(
        builder: (context, ref, child) {
          final sessionAsync = ref.watch(sessionProvider);

          return sessionAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => ErrorRetryView(
              error: err.toString(),
              onRetry: () => ref.refresh(sessionProvider),
            ),
            data: (session) {
              if (session == null) {
                return const EmptyStateView(
                  icon: Icons.info,
                  title: 'ログインが必要です',
                  description: 'ホーム画面からログインしてください',
                );
              }

              return _buildTrainingDashboard(
                context,
                ref,
                session.companyId,
                session.employeeId,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTrainingDashboard(
    BuildContext context,
    WidgetRef ref,
    String companyId,
    String employeeId,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header with training period info
          _buildTrainingHeader(context),

          // Deadline countdown
          _buildDeadlineWidget(context),

          // Module progress cards
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '学習モジュール',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ..._buildModuleCards(
                  context,
                  ref,
                  companyId,
                  employeeId,
                ),
              ],
            ),
          ),

          // Footer info
          _buildFooterInfo(context),
        ],
      ),
    );
  }

  Widget _buildTrainingHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withOpacity(0.7),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tier 1 Training',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '本番環境昇格前の自習期間です',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '期間',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    Text(
                      '2026年9月16日～22日',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'モジュール数',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const Text(
                      '4つの研修',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlineWidget(BuildContext context) {
    final now = DateTime.now();
    final deadline = DateTime.parse(_trainingDeadline);
    final daysRemaining = deadline.difference(now).inDays;
    final hoursRemaining = deadline.difference(now).inHours % 24;

    final isWarning = daysRemaining <= 2;
    final isOverdue = now.isAfter(deadline);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOverdue
            ? Colors.red.withOpacity(0.1)
            : isWarning
                ? Colors.orange.withOpacity(0.1)
                : Colors.blue.withOpacity(0.1),
        border: Border.all(
          color: isOverdue
              ? Colors.red
              : isWarning
                  ? Colors.orange
                  : Colors.blue,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isOverdue ? Icons.error : Icons.schedule,
            color: isOverdue
                ? Colors.red
                : isWarning
                    ? Colors.orange
                    : Colors.blue,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '期限まであと',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (!isOverdue)
                  Text(
                    '$daysRemaining日 $hoursRemaining時間',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isWarning ? Colors.orange : Colors.blue,
                    ),
                  )
                else
                  const Text(
                    '期限を超過しています',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildModuleCards(
    BuildContext context,
    WidgetRef ref,
    String companyId,
    String employeeId,
  ) {
    return [
      _ModuleProgressCard(
        moduleId: tierOneModuleIds[0],
        title: 'Platform技術概要',
        subtitle: 'Firebase・Cloud Functions・Firestore',
        duration: '4時間',
        moduleIndex: 0,
        companyId: companyId,
        employeeId: employeeId,
        ref: ref,
      ),
      const SizedBox(height: 12),
      _ModuleProgressCard(
        moduleId: tierOneModuleIds[1],
        title: 'Operations・監視体制',
        subtitle: '監視・性能最適化・エラーハンドリング',
        duration: '4時間',
        moduleIndex: 1,
        companyId: companyId,
        employeeId: employeeId,
        ref: ref,
      ),
      const SizedBox(height: 12),
      _ModuleProgressCard(
        moduleId: tierOneModuleIds[2],
        title: 'Content Production・配信戦略',
        subtitle: 'コンテンツ企画・多形式配信・AI生成',
        duration: '4時間',
        moduleIndex: 2,
        companyId: companyId,
        employeeId: employeeId,
        ref: ref,
      ),
      const SizedBox(height: 12),
      _ModuleProgressCard(
        moduleId: tierOneModuleIds[3],
        title: 'GTM Strategy・営業展開',
        subtitle: '営業サイクル・価格設定・成功メトリクス',
        duration: '4時間',
        moduleIndex: 3,
        companyId: companyId,
        employeeId: employeeId,
        ref: ref,
      ),
    ];
  }

  Widget _buildFooterInfo(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 24),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '修了条件',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _buildConditionItem('✓', '各モジュールのクイズで80%以上の正答率'),
          _buildConditionItem('✓', 'すべてのモジュールを期限までに完了'),
          _buildConditionItem('✓', '修了により修了証が自動発行'),
          const SizedBox(height: 16),
          Text(
            '注意: Sep 22 23:59 JST を超えた提出は受け付けません',
            style: TextStyle(
              fontSize: 12,
              color: Colors.red[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToModule(
    BuildContext context,
    WidgetRef ref,
    String companyId,
    String moduleId,
  ) async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      final moduleService = ref.read(moduleServiceProvider);
      final module = await moduleService.getModule(moduleId);

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LessonScreen(
            module: module,
            companyId: companyId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('モジュールの読み込みに失敗しました: $e')),
        );
      }
    } finally {
      _isNavigating = false;
    }
  }
}

/// Module progress card widget
class _ModuleProgressCard extends StatefulWidget {
  final String moduleId;
  final String title;
  final String subtitle;
  final String duration;
  final int moduleIndex;
  final String companyId;
  final String employeeId;
  final WidgetRef ref;

  const _ModuleProgressCard({
    required this.moduleId,
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.moduleIndex,
    required this.companyId,
    required this.employeeId,
    required this.ref,
  });

  @override
  State<_ModuleProgressCard> createState() => _ModuleProgressCardState();
}

class _ModuleProgressCardState extends State<_ModuleProgressCard> {
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        // Fetch enrollment data for this module
        final enrollmentAsync = ref.watch(
          enrollmentServiceProvider.select(
            (service) => Future.value(
              service.getEnrollment(
                companyId: widget.companyId,
                employeeId: widget.employeeId,
                moduleId: widget.moduleId,
              ),
            ),
          ),
        );

        return enrollmentAsync.when(
          loading: () => _buildSkeletonCard(),
          error: (err, stack) => _buildCard(
            context,
            completionPercent: 0,
            isPassed: false,
            lessonCount: 4,
            quizCount: 5,
          ),
          data: (enrollment) {
            final completionPercent = enrollment != null
                ? ((enrollment.lessonsCompleted / 4) * 100).toInt()
                : 0;
            final isPassed = enrollment?.isPassed ?? false;
            return _buildCard(
              context,
              completionPercent: completionPercent,
              isPassed: isPassed,
              lessonCount: 4,
              quizCount: 5,
            );
          },
        );
      },
    );
  }

  Widget _buildSkeletonCard() {
    return SkeletonLoader(
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required int completionPercent,
    required bool isPassed,
    required int lessonCount,
    required int quizCount,
  }) {
    return GestureDetector(
      onTap: () => _navigateToModule(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPassed ? Colors.green : Colors.grey[300]!,
            width: isPassed ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isPassed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Text(
                      '修了',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 6),
                Text(
                  widget.duration,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.menu_book,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 6),
                Text(
                  'レッスン ${widget.lessonCount}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.quiz,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 6),
                Text(
                  'クイズ ${widget.quizCount}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: completionPercent / 100,
                minHeight: 6,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  isPassed ? Colors.green : Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '進捗: $completionPercent%',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToModule(BuildContext context) async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      final moduleService = widget.ref.read(moduleServiceProvider);
      final module = await moduleService.getModule(widget.moduleId);

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LessonScreen(
            module: module,
            companyId: widget.companyId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('モジュールの読み込みに失敗しました: $e')),
        );
      }
    } finally {
      _isNavigating = false;
    }
  }
}
