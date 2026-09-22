import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/models/training_progress_model.dart';
import '../../providers/service_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/session_provider.dart';
import '../lesson/lesson_screen.dart';
import '../../widgets/error_retry_view.dart';
import 'user_feedback_screen.dart';

// Tier 1 Training のモジュールID一覧（プロバイダー・画面の両方から参照するためトップレベルで定義）
const List<String> kTierOneModuleIds = [
  'tier1-platform-tech',
  'tier1-operations',
  'tier1-content-production',
  'tier1-gtm-strategy',
];

const Map<String, String> kTierOneModuleTitles = {
  'tier1-platform-tech': 'Platform技術概要',
  'tier1-operations': 'Operations・監視体制',
  'tier1-content-production': 'Content Production・配信戦略',
  'tier1-gtm-strategy': 'GTM Strategy・営業展開',
};

const Map<String, String> kTierOneModuleSubtitles = {
  'tier1-platform-tech': 'Firebase・Cloud Functions・Firestore',
  'tier1-operations': '監視・性能最適化・エラーハンドリング',
  'tier1-content-production': 'コンテンツ企画・多形式配信・AI生成',
  'tier1-gtm-strategy': '営業サイクル・価格設定・成功メトリクス',
};

// グラフのX軸ラベル用の短縮表記
const Map<String, String> kTierOneModuleShortLabels = {
  'tier1-platform-tech': 'Platform',
  'tier1-operations': 'Ops',
  'tier1-content-production': 'Content',
  'tier1-gtm-strategy': 'GTM',
};

// Firestore リアルタイムプロバイダー: 自分自身の Tier 1 Training 進捗状況
final trainingProgressProvider =
    StreamProvider.autoDispose<List<TrainingProgress>>((ref) {
  final session = ref.watch(sessionProvider);
  final employee = session.employee;
  final company = session.company;
  if (employee == null || company == null) {
    return Stream.value(const []);
  }

  return ref
      .watch(firestoreProvider)
      .collection('companies')
      .doc(company.id)
      .collection('trainingAttempts')
      .where('employeeId', isEqualTo: employee.id)
      .where('moduleId', whereIn: kTierOneModuleIds)
      .orderBy('attemptedAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => TrainingProgress.fromMap(doc.data()))
          .toList());
});

// 会社全体（チームレポート用）の Tier 1 Training 進捗状況
final companyTrainingProgressProvider =
    StreamProvider.autoDispose<List<TrainingProgress>>((ref) {
  final session = ref.watch(sessionProvider);
  final company = session.company;
  if (company == null) {
    return Stream.value(const []);
  }

  return ref
      .watch(firestoreProvider)
      .collection('companies')
      .doc(company.id)
      .collection('trainingAttempts')
      .where('moduleId', whereIn: kTierOneModuleIds)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => TrainingProgress.fromMap(doc.data()))
          .toList());
});

// 修了証リアルタイムプロバイダー
final trainingCertificateProvider =
    StreamProvider.autoDispose<TrainingCertificate?>((ref) {
  final session = ref.watch(sessionProvider);
  final employee = session.employee;
  final company = session.company;
  if (employee == null || company == null) {
    return Stream.value(null);
  }

  return ref
      .watch(firestoreProvider)
      .collection('companies')
      .doc(company.id)
      .collection('trainingCertificates')
      .where('employeeId', isEqualTo: employee.id)
      .limit(1)
      .snapshots()
      .map((snapshot) => snapshot.docs.isEmpty
          ? null
          : TrainingCertificate.fromMap(
              snapshot.docs.first.id, snapshot.docs.first.data()));
});

/// レポートの集計対象（個人 / チーム全体）
enum _ReportScope { individual, team }

/// Tier 1 Training Dashboard: Sep 16-22 自習期間の学習進捗管理画面
class TrainingDashboardScreen extends ConsumerStatefulWidget {
  const TrainingDashboardScreen({super.key});

  @override
  ConsumerState<TrainingDashboardScreen> createState() =>
      _TrainingDashboardScreenState();
}

class _TrainingDashboardScreenState
    extends ConsumerState<TrainingDashboardScreen> {
  static final DateTime _trainingPeriodStart = DateTime(2026, 9, 16);
  static final DateTime _trainingPeriodEnd = DateTime(2026, 9, 22);
  static const String _trainingDeadline = '2026-09-22T23:59:59+09:00';

  _ReportScope _reportScope = _ReportScope.individual;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tier 1 研修'),
        elevation: 0,
      ),
      body: !session.isSignedIn
          ? const Center(child: Text('ログインが必要です'))
          : _buildTrainingDashboard(context),
    );
  }

  Widget _buildTrainingDashboard(BuildContext context) {
    final progressAsync = ref.watch(trainingProgressProvider);
    final certificateAsync = ref.watch(trainingCertificateProvider);

    return progressAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => ErrorRetryView(
        message: '進捗情報の読み込みに失敗しました: $err',
        onRetry: () => ref.refresh(trainingProgressProvider),
      ),
      data: (progressList) => SingleChildScrollView(
        child: Column(
          children: [
            // Header with training period info
            _buildTrainingHeader(context),

            // Certificate banner (issued once all modules are passed)
            if (certificateAsync.valueOrNull != null)
              _buildCertificateBanner(context, certificateAsync.valueOrNull!),

            // Deadline countdown
            _buildDeadlineWidget(context),

            // Module progress cards with real-time data
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
                  ..._buildModuleCards(progressList),
                ],
              ),
            ),

            // Progress analytics / report section
            _buildAnalyticsSection(context, progressList),

            // Footer info
            _buildFooterInfo(context),
          ],
        ),
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
                    const Text(
                      '2026年9月16日～22日',
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

  List<Widget> _buildModuleCards(List<TrainingProgress> progressList) {
    TrainingProgress? progressForModule(String moduleId) {
      for (final p in progressList) {
        if (p.moduleId == moduleId) return p;
      }
      return null;
    }

    final cards = <Widget>[];
    for (var i = 0; i < kTierOneModuleIds.length; i++) {
      final moduleId = kTierOneModuleIds[i];
      if (i > 0) cards.add(const SizedBox(height: 12));
      cards.add(_ModuleProgressCard(
        moduleId: moduleId,
        title: kTierOneModuleTitles[moduleId]!,
        subtitle: kTierOneModuleSubtitles[moduleId]!,
        duration: '4時間',
        progress: progressForModule(moduleId),
      ));
    }
    return cards;
  }

  Widget _buildCertificateBanner(
    BuildContext context,
    TrainingCertificate certificate,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        border: Border.all(color: Colors.green),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Colors.green, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '修了証が発行されました',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '証明書番号: ${certificate.certificateNumber}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsSection(
    BuildContext context,
    List<TrainingProgress> individualProgress,
  ) {
    final companyProgressAsync = ref.watch(companyTrainingProgressProvider);
    final isTeamScope = _reportScope == _ReportScope.team;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '進捗分析レポート',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              _buildScopeToggle(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isTeamScope ? '会社全体の学習進捗のサマリーです' : '自分の学習進捗のサマリーです',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          if (!isTeamScope)
            _buildReportBody(context, individualProgress)
          else
            companyProgressAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => ErrorRetryView(
                message: 'チームの進捗情報の読み込みに失敗しました: $err',
                onRetry: () => ref.refresh(companyTrainingProgressProvider),
              ),
              data: (companyProgress) =>
                  _buildReportBody(context, companyProgress),
            ),
        ],
      ),
    );
  }

  Widget _buildScopeToggle() {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('個人'),
          selected: _reportScope == _ReportScope.individual,
          onSelected: (_) =>
              setState(() => _reportScope = _ReportScope.individual),
        ),
        ChoiceChip(
          label: const Text('チーム'),
          selected: _reportScope == _ReportScope.team,
          onSelected: (_) => setState(() => _reportScope = _ReportScope.team),
        ),
      ],
    );
  }

  Widget _buildReportBody(
    BuildContext context,
    List<TrainingProgress> progress,
  ) {
    final report = TrainingProgressReport.build(
      moduleIds: kTierOneModuleIds,
      progress: progress,
      periodStart: _trainingPeriodStart,
      periodEnd: _trainingPeriodEnd,
    );

    if (progress.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'まだ学習記録がありません',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      children: [
        _buildSummaryTiles(report),
        const SizedBox(height: 20),
        _buildCompletionRateChart(context, report),
        const SizedBox(height: 20),
        _buildTrendChart(context, report),
        const SizedBox(height: 20),
        _buildModuleStatTable(report),
      ],
    );
  }

  Widget _buildSummaryTiles(TrainingProgressReport report) {
    final averageDurationMinutes = report.moduleStats.isEmpty
        ? 0
        : report.moduleStats.fold<int>(
                0, (sum, s) => sum + s.averageStudyDuration.inMinutes) ~/
            report.moduleStats.length;

    final tiles = [
      _StatTile(
        label: '完了率',
        value: '${(report.overallCompletionRate * 100).toStringAsFixed(0)}%',
        icon: Icons.check_circle,
        color: Colors.green,
      ),
      _StatTile(
        label: '完了モジュール',
        value: '${report.completedModules}/${report.totalModules}',
        icon: Icons.menu_book,
        color: Colors.blue,
      ),
      _StatTile(
        label: '平均スコア',
        value: '${report.overallAverageScore.toStringAsFixed(0)}点',
        icon: Icons.grade,
        color: Colors.orange,
      ),
      _StatTile(
        label: '平均学習時間',
        value: _formatDuration(Duration(minutes: averageDurationMinutes)),
        icon: Icons.schedule,
        color: Colors.purple,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.4,
      children: tiles,
    );
  }

  Widget _buildCompletionRateChart(
    BuildContext context,
    TrainingProgressReport report,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'モジュール別 完了率',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: 100,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: 25,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}%',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= report.moduleStats.length) {
                          return const SizedBox.shrink();
                        }
                        final moduleId = report.moduleStats[index].moduleId;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            kTierOneModuleShortLabels[moduleId] ?? '',
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < report.moduleStats.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: report.moduleStats[i].completionRate * 100,
                          color: Theme.of(context).primaryColor,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart(
    BuildContext context,
    TrainingProgressReport report,
  ) {
    final trend = report.dailyTrend;
    var cumulative = 0;
    final spots = <FlSpot>[];
    for (var i = 0; i < trend.length; i++) {
      cumulative += trend[i].completedCount;
      spots.add(FlSpot(i.toDouble(), cumulative.toDouble()));
    }
    final maxY = cumulative == 0 ? 1.0 : cumulative.toDouble();
    final dateFormat = DateFormat('M/d');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '期間中の修了推移（累計）',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: trend.isEmpty
                ? const Center(child: Text('データがありません'))
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: maxY,
                      gridData:
                          const FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) => Text(
                              '${value.toInt()}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= trend.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  dateFormat.format(trend[index].date),
                                  style: const TextStyle(fontSize: 9),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: Colors.blue,
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Colors.blue.withOpacity(0.12),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleStatTable(TrainingProgressReport report) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'モジュール別詳細',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < report.moduleStats.length; i++) ...[
            _buildModuleStatRow(report.moduleStats[i]),
            if (i < report.moduleStats.length - 1) const Divider(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildModuleStatRow(ModuleProgressStat stat) {
    final title = kTierOneModuleTitles[stat.moduleId] ?? stat.moduleId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '完了率 ${(stat.completionRate * 100).toStringAsFixed(0)}%  ・  '
          '平均スコア ${stat.averageScore.toStringAsFixed(0)}点  ・  '
          '平均学習時間 ${_formatDuration(stat.averageStudyDuration)}  ・  '
          '受講回数 ${stat.recordCount}件',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes <= 0) return '-';
    final hours = d.inMinutes ~/ 60;
    final minutes = d.inMinutes % 60;
    if (hours <= 0) return '$minutes分';
    return '$hours時間$minutes分';
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UserFeedbackScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.feedback),
              label: const Text('フィードバックを送信'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionItem(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(color: Colors.green)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Module progress card widget: [progress]が非nullならFirestoreの実データを表示し、
/// nullなら未受講として表示する（受講開始前はtrainingAttemptsにレコードが無いため）。
class _ModuleProgressCard extends ConsumerStatefulWidget {
  final String moduleId;
  final String title;
  final String subtitle;
  final String duration;
  final TrainingProgress? progress;

  const _ModuleProgressCard({
    required this.moduleId,
    required this.title,
    required this.subtitle,
    required this.duration,
    this.progress,
  });

  @override
  ConsumerState<_ModuleProgressCard> createState() =>
      _ModuleProgressCardState();
}

class _ModuleProgressCardState extends ConsumerState<_ModuleProgressCard> {
  static const int _totalLessons = 4;
  static const int _totalQuizQuestions = 5;

  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final isPassed = progress?.isPassed ?? false;
    final completionPercent = progress == null
        ? 0
        : isPassed
            ? 100
            : ((progress.lessonsCompleted / _totalLessons) * 100)
                .clamp(0, 100)
                .toInt();

    return GestureDetector(
      onTap: _isNavigating ? null : () => _navigateToModule(context),
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
                  'レッスン $_totalLessons',
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
                  'クイズ $_totalQuizQuestions',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(width: 16),
                  Icon(
                    Icons.grade,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'スコア ${progress.maxScore}点',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
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

  Future<void> _navigateToModule(BuildContext context) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      final module =
          await ref.read(contentServiceProvider).getModule(widget.moduleId);

      if (!mounted) return;

      if (module == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('モジュールが見つかりませんでした')),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LessonScreen(module: module),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('モジュールの読み込みに失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }
}
