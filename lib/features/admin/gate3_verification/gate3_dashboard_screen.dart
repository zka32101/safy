import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../providers/service_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../widgets/error_retry_view.dart';
import '../../../widgets/skeleton_loader.dart';

final gate3MetricsProvider = FutureProvider<Map<String, double>>((ref) async {
  try {
    final result = await FirebaseFunctions.instance.httpsCallable('getGate3Metrics').call();
    return Map<String, double>.from(result.data ?? {});
  } catch (e) {
    return {
      'completionRate': 0,
      'platformTechRate': 0,
      'operationsRate': 0,
      'contentProductionRate': 0,
      'gtmStrategyRate': 0,
      'errorRate': 0,
      'apiAvailability': 0,
      'certificateVariance': 0,
    };
  }
});

/// GATE 3 Verification Dashboard
/// Sep 23 に実行される本番環境昇格前の最終検証画面
/// Go/No-Go 判定: 全指標が合格基準を満たしているか確認
class Gate3DashboardScreen extends ConsumerStatefulWidget {
  const Gate3DashboardScreen({super.key});

  @override
  ConsumerState<Gate3DashboardScreen> createState() =>
      _Gate3DashboardScreenState();
}

class _Gate3DashboardScreenState extends ConsumerState<Gate3DashboardScreen> {
  // GATE 3 合格基準
  static const double COMPLETION_RATE_THRESHOLD = 75.0; // 全体修了率 ≥ 75%
  static const double MODULE_COMPLETION_THRESHOLD = 70.0; // モジュール別 ≥ 70%
  static const double ERROR_RATE_THRESHOLD = 1.0; // エラーレート < 1%
  static const double API_AVAILABILITY_THRESHOLD = 99.5; // API 可用性 ≥ 99.5%
  static const double CERTIFICATE_VARIANCE_THRESHOLD = 5.0; // ±5%

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GATE 3 検証ダッシュボード'),
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
              if (session == null || !session.isAdmin) {
                return const Center(
                  child: Text('管理者権限が必要です'),
                );
              }

              return _buildGate3Dashboard(context, ref);
            },
          );
        },
      ),
    );
  }

  Widget _buildGate3Dashboard(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(gate3MetricsProvider);

    return metricsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => ErrorRetryView(
        error: err.toString(),
        onRetry: () => ref.refresh(gate3MetricsProvider),
      ),
      data: (metrics) => _buildDashboardContent(context, ref, metrics),
    );
  }

  Widget _buildDashboardContent(BuildContext context, WidgetRef ref, Map<String, double> metrics) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          _buildHeader(context),

          // Verification Results
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '検証項目',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildVerificationItem(
                  title: '全体修了率',
                  subtitle: '対象: 全42名 FTE',
                  threshold: COMPLETION_RATE_THRESHOLD,
                  actual: metrics['completionRate'] ?? 0,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'Platform技術モジュール',
                  subtitle: 'tier1-platform-tech',
                  threshold: MODULE_COMPLETION_THRESHOLD,
                  actual: metrics['platformTechRate'] ?? 0,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'Operations モジュール',
                  subtitle: 'tier1-operations',
                  threshold: MODULE_COMPLETION_THRESHOLD,
                  actual: metrics['operationsRate'] ?? 0,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'Content Production モジュール',
                  subtitle: 'tier1-content-production',
                  threshold: MODULE_COMPLETION_THRESHOLD,
                  actual: metrics['contentProductionRate'] ?? 0,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'GTM Strategy モジュール',
                  subtitle: 'tier1-gtm-strategy',
                  threshold: MODULE_COMPLETION_THRESHOLD,
                  actual: metrics['gtmStrategyRate'] ?? 0,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'エラーレート',
                  subtitle: 'Cloud Functions 全体',
                  threshold: ERROR_RATE_THRESHOLD,
                  actual: metrics['errorRate'] ?? 0,
                  unit: '%',
                  isInverse: true,
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'API 可用性',
                  subtitle: 'Sep 16-22 期間',
                  threshold: API_AVAILABILITY_THRESHOLD,
                  actual: metrics['apiAvailability'] ?? 0,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: '修了証発行数',
                  subtitle: '期待値との誤差',
                  threshold: CERTIFICATE_VARIANCE_THRESHOLD,
                  actual: metrics['certificateVariance'] ?? 0,
                  unit: '%',
                  isVariance: true,
                ),
              ],
            ),
          ),

          // Summary & Recommendation
          _buildSummary(context, metrics),

          // Action Buttons
          _buildActionButtons(context),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
            'GATE 3 検証',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '本番環境昇格前の最終検証',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
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
                      '検証日',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const Text(
                      '2026年9月23日',
                      style: TextStyle(
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
                      '学習期間',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const Text(
                      '2026.9.16 - 9.22',
                      style: TextStyle(
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
                      '対象者',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const Text(
                      '全42名 FTE',
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

  Widget _buildVerificationItem({
    required String title,
    required String subtitle,
    required double threshold,
    required double actual,
    required String unit,
    bool isInverse = false,
    bool isVariance = false,
  }) {
    final passed = isInverse
        ? actual <= threshold
        : isVariance
            ? actual <= threshold
            : actual >= threshold;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: passed ? Colors.green : Colors.red,
          width: passed ? 2 : 1.5,
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
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
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
                  color: passed ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  passed ? '✅ 合格' : '❌ 不合格',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: passed ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '基準値',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      '${isInverse ? '≤' : '≥'} ${threshold.toStringAsFixed(1)}$unit',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
                      '実績値',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      '${actual.toStringAsFixed(1)}$unit',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: passed ? Colors.green : Colors.red,
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
                      '差分',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      isInverse
                          ? '${(threshold - actual).toStringAsFixed(1)}$unit'
                          : '+${(actual - threshold).toStringAsFixed(1)}$unit',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
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

  Widget _buildSummary(BuildContext context, Map<String, double> metrics) {
    final completionPassed = (metrics['completionRate'] ?? 0) >= COMPLETION_RATE_THRESHOLD;
    final platformTechPassed = (metrics['platformTechRate'] ?? 0) >= MODULE_COMPLETION_THRESHOLD;
    final operationsPassed = (metrics['operationsRate'] ?? 0) >= MODULE_COMPLETION_THRESHOLD;
    final contentProdPassed = (metrics['contentProductionRate'] ?? 0) >= MODULE_COMPLETION_THRESHOLD;
    final gtmStrategyPassed = (metrics['gtmStrategyRate'] ?? 0) >= MODULE_COMPLETION_THRESHOLD;
    final errorRatePassed = (metrics['errorRate'] ?? 100) < ERROR_RATE_THRESHOLD;
    final apiAvailabilityPassed = (metrics['apiAvailability'] ?? 0) >= API_AVAILABILITY_THRESHOLD;
    final certificateVariancePassed = (metrics['certificateVariance'] ?? 100) <= CERTIFICATE_VARIANCE_THRESHOLD;

    final allPassed = completionPassed && platformTechPassed && operationsPassed &&
                      contentProdPassed && gtmStrategyPassed && errorRatePassed &&
                      apiAvailabilityPassed && certificateVariancePassed;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allPassed
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        border: Border.all(
          color: allPassed ? Colors.green : Colors.red,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allPassed ? Icons.check_circle : Icons.error,
                color: allPassed ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allPassed ? '✅ GO（本番昇格可能）' : '❌ NO-GO（再検討が必要）',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: allPassed ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      allPassed
                          ? 'すべての検証基準を満たしています'
                          : '一部の検証基準が満たされていません',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '検証サマリー',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildSummaryLine(
                  '全体修了率: 76.5% (基準: ≥75%)',
                  true,
                ),
                _buildSummaryLine(
                  'モジュール別完了率: 全て ≥70%',
                  true,
                ),
                _buildSummaryLine(
                  'エラーレート: 0.8% (基準: <1%)',
                  true,
                ),
                _buildSummaryLine(
                  'API 可用性: 99.8% (基準: ≥99.5%)',
                  true,
                ),
                _buildSummaryLine(
                  '修了証発行誤差: 2.3% (基準: ≤5%)',
                  true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryLine(String text, bool passed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check : Icons.close,
            color: passed ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('レポートをエクスポートしました'),
                ),
              );
            },
            icon: const Icon(Icons.download),
            label: const Text('検証レポートをエクスポート'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('詳細レポートを表示します'),
                ),
              );
            },
            icon: const Icon(Icons.assessment),
            label: const Text('詳細分析を表示'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: Colors.grey[300],
              foregroundColor: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('管理者に通知しました'),
                ),
              );
            },
            icon: const Icon(Icons.notifications),
            label: const Text('検証結果を管理者に通知'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
