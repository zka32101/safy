import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/firebase_providers.dart';
import '../../../providers/session_provider.dart';
import '../../../widgets/error_retry_view.dart';
import '../../../widgets/skeleton_loader.dart';

final gate3MetricsProvider = FutureProvider<Map<String, double>>((ref) async {
  // firestoreProvider と同じ DI パターンに揃え、FirebaseFunctions.instance を
  // 直接ハードコードしない(テスト時に差し替え可能にする)。
  final functions = ref.watch(functionsProvider);
  final result = await functions.httpsCallable('getGate3Metrics').call();

  final rawData = result.data;
  if (rawData is! Map) {
    // データ不整合はここで検知し、AsyncValue.error として画面側に伝播させる。
    // 以前はここで例外を握りつぶして全項目0のダミー値を返しており、
    // 取得失敗なのか実際に指標が悪いのか見分けがつかなくなっていた。
    throw StateError('GATE 3 指標データの形式が不正です');
  }

  // Cloud Functions からの数値は int で返ってくることがあり、
  // Map<String, double>.from() では実行時に型キャストエラーになりうるため
  // num -> double へ安全に変換する。
  return rawData.map(
    (key, value) => MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0.0),
  );
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

  /// 各指標の合格判定ロジックを一箇所に集約する。
  /// 以前は「項目カード」と「検証サマリー」で判定条件(< と <=)がズレており、
  /// 同じ実績値でもカードとサマリーで合否表示が食い違うことがあった。
  static bool _isPassed({
    required double actual,
    required double threshold,
    bool isInverse = false,
    bool isVariance = false,
  }) {
    if (isInverse) return actual < threshold; // 例: エラーレート < 1%
    if (isVariance) return actual.abs() <= threshold; // 例: 誤差 ±5% 以内
    return actual >= threshold; // 例: 修了率 ≥ 75%
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GATE 3 検証ダッシュボード'),
        elevation: 0,
      ),
      body: Consumer(
        builder: (context, ref, child) {
          // SessionState (lib/providers/session_provider.dart) は同期的な単純クラスで
          // AsyncValue ではないため、.when()/.future/.valueOrNull は呼べない
          // (呼ぶとコンパイルエラーになる)。isSignedIn/isAdmin を直接参照する。
          final session = ref.watch(sessionProvider);

          if (!session.isSignedIn) {
            return const Center(child: Text('セッションが見つかりません'));
          }
          if (!session.isAdmin) {
            return const Center(
              child: Text('管理者権限が必要です'),
            );
          }

          return _buildGate3Dashboard(context, ref);
        },
      ),
    );
  }

  Widget _buildGate3Dashboard(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(gate3MetricsProvider);

    return metricsAsync.when(
      loading: () => const SkeletonList(),
      error: (err, stack) => ErrorRetryView(
        message: 'GATE 3 指標の取得に失敗しました: $err',
        onRetry: () => ref.refresh(gate3MetricsProvider),
      ),
      data: (metrics) => _buildDashboardContent(context, ref, metrics),
    );
  }

  Widget _buildDashboardContent(BuildContext context, WidgetRef ref, Map<String, double> metrics) {
    final completionRate = metrics['completionRate'] ?? 0;
    final platformTechRate = metrics['platformTechRate'] ?? 0;
    final operationsRate = metrics['operationsRate'] ?? 0;
    final contentProductionRate = metrics['contentProductionRate'] ?? 0;
    final gtmStrategyRate = metrics['gtmStrategyRate'] ?? 0;
    final errorRate = metrics['errorRate'] ?? 100;
    final apiAvailability = metrics['apiAvailability'] ?? 0;
    final certificateVariance = metrics['certificateVariance'] ?? 100;

    // 8項目の合否をここで一度だけ計算し、項目カードと検証サマリーの両方で
    // 同じ結果(itemResults)を参照させることで判定のズレを防ぐ。
    final itemResults = <String, bool>{
      '全体修了率': _isPassed(actual: completionRate, threshold: COMPLETION_RATE_THRESHOLD),
      'Platform技術モジュール': _isPassed(actual: platformTechRate, threshold: MODULE_COMPLETION_THRESHOLD),
      'Operations モジュール': _isPassed(actual: operationsRate, threshold: MODULE_COMPLETION_THRESHOLD),
      'Content Production モジュール': _isPassed(actual: contentProductionRate, threshold: MODULE_COMPLETION_THRESHOLD),
      'GTM Strategy モジュール': _isPassed(actual: gtmStrategyRate, threshold: MODULE_COMPLETION_THRESHOLD),
      'エラーレート': _isPassed(actual: errorRate, threshold: ERROR_RATE_THRESHOLD, isInverse: true),
      'API 可用性': _isPassed(actual: apiAvailability, threshold: API_AVAILABILITY_THRESHOLD),
      '修了証発行数': _isPassed(actual: certificateVariance, threshold: CERTIFICATE_VARIANCE_THRESHOLD, isVariance: true),
    };
    final passedCount = itemResults.values.where((p) => p).length;
    final totalCount = itemResults.length;

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
                const SizedBox(height: 12),
                _buildProgressOverview(passedCount, totalCount),
                const SizedBox(height: 16),
                _buildVerificationItem(
                  title: '全体修了率',
                  subtitle: '対象: 全42名 FTE',
                  threshold: COMPLETION_RATE_THRESHOLD,
                  actual: completionRate,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'Platform技術モジュール',
                  subtitle: 'tier1-platform-tech',
                  threshold: MODULE_COMPLETION_THRESHOLD,
                  actual: platformTechRate,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'Operations モジュール',
                  subtitle: 'tier1-operations',
                  threshold: MODULE_COMPLETION_THRESHOLD,
                  actual: operationsRate,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'Content Production モジュール',
                  subtitle: 'tier1-content-production',
                  threshold: MODULE_COMPLETION_THRESHOLD,
                  actual: contentProductionRate,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'GTM Strategy モジュール',
                  subtitle: 'tier1-gtm-strategy',
                  threshold: MODULE_COMPLETION_THRESHOLD,
                  actual: gtmStrategyRate,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'エラーレート',
                  subtitle: 'Cloud Functions 全体',
                  threshold: ERROR_RATE_THRESHOLD,
                  actual: errorRate,
                  unit: '%',
                  isInverse: true,
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: 'API 可用性',
                  subtitle: 'Sep 16-22 期間',
                  threshold: API_AVAILABILITY_THRESHOLD,
                  actual: apiAvailability,
                  unit: '%',
                ),
                const SizedBox(height: 12),
                _buildVerificationItem(
                  title: '修了証発行数',
                  subtitle: '期待値との誤差',
                  threshold: CERTIFICATE_VARIANCE_THRESHOLD,
                  actual: certificateVariance,
                  unit: '%',
                  isVariance: true,
                ),
              ],
            ),
          ),

          // Summary & Recommendation
          _buildSummary(context, metrics, itemResults, passedCount, totalCount),

          // Action Buttons
          _buildActionButtons(context),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 認定進捗の全体像を一目で把握できるよう、合格数と進捗バーを表示する。
  Widget _buildProgressOverview(int passedCount, int totalCount) {
    final ratio = totalCount == 0 ? 0.0 : passedCount / totalCount;
    final allPassed = totalCount > 0 && passedCount == totalCount;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '認定進捗',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                '$passedCount / $totalCount 項目が合格',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: allPassed ? Colors.green[700] : Colors.orange[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
              color: allPassed ? Colors.green : Colors.orange,
            ),
          ),
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
    final passed = _isPassed(
      actual: actual,
      threshold: threshold,
      isInverse: isInverse,
      isVariance: isVariance,
    );

    // 進捗バー: 「大きいほど良い」指標は 実績/100 を、
    // 「小さいほど良い」指標(エラーレート・誤差)は 1 - 実績/(閾値の2倍) を目安に正規化する。
    double progressValue;
    if (isInverse || isVariance) {
      final denom = threshold > 0 ? threshold * 2 : 1;
      progressValue = (1 - (actual.abs() / denom)).clamp(0.0, 1.0);
    } else {
      progressValue = (actual / 100).clamp(0.0, 1.0);
    }

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
                      '${isInverse ? '<' : isVariance ? '≤' : '≥'} ${threshold.toStringAsFixed(1)}$unit',
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
                      isInverse || isVariance
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
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 6,
              backgroundColor: Colors.grey[200],
              color: passed ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(
    BuildContext context,
    Map<String, double> metrics,
    Map<String, bool> itemResults,
    int passedCount,
    int totalCount,
  ) {
    final allPassed = totalCount > 0 && passedCount == totalCount;

    final completionRate = metrics['completionRate'] ?? 0;
    final errorRate = metrics['errorRate'] ?? 100;
    final apiAvailability = metrics['apiAvailability'] ?? 0;
    final certificateVariance = metrics['certificateVariance'] ?? 100;
    final modulePassed = (itemResults['Platform技術モジュール'] ?? false) &&
        (itemResults['Operations モジュール'] ?? false) &&
        (itemResults['Content Production モジュール'] ?? false) &&
        (itemResults['GTM Strategy モジュール'] ?? false);

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
                          : '$totalCount項目中$passedCount項目のみ基準を満たしています',
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
                  '全体修了率: ${completionRate.toStringAsFixed(1)}% '
                  '(基準: ≥${COMPLETION_RATE_THRESHOLD.toStringAsFixed(0)}%)',
                  itemResults['全体修了率'] ?? false,
                ),
                _buildSummaryLine(
                  modulePassed
                      ? 'モジュール別完了率: 全て ≥${MODULE_COMPLETION_THRESHOLD.toStringAsFixed(0)}%'
                      : 'モジュール別完了率: 一部が基準未達 (基準: ≥${MODULE_COMPLETION_THRESHOLD.toStringAsFixed(0)}%)',
                  modulePassed,
                ),
                _buildSummaryLine(
                  'エラーレート: ${errorRate.toStringAsFixed(1)}% '
                  '(基準: <${ERROR_RATE_THRESHOLD.toStringAsFixed(0)}%)',
                  itemResults['エラーレート'] ?? false,
                ),
                _buildSummaryLine(
                  'API 可用性: ${apiAvailability.toStringAsFixed(1)}% '
                  '(基準: ≥${API_AVAILABILITY_THRESHOLD.toStringAsFixed(1)}%)',
                  itemResults['API 可用性'] ?? false,
                ),
                _buildSummaryLine(
                  '修了証発行誤差: ${certificateVariance.toStringAsFixed(1)}% '
                  '(基準: ≤${CERTIFICATE_VARIANCE_THRESHOLD.toStringAsFixed(0)}%)',
                  itemResults['修了証発行数'] ?? false,
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
