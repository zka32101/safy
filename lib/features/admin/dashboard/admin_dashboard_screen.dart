import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/enrollment_model.dart';
import '../../../data/models/team_model.dart';
import '../../../core/dashboard_analytics.dart';
import '../../../core/churn_risk.dart';
import '../../../providers/firebase_providers.dart';
import '../../../providers/service_providers.dart';
import '../../../providers/session_provider.dart';
import '../reminder/reminder_screen.dart';
import '../report_export/report_export_screen.dart';
import '../pass_threshold/pass_threshold_settings_screen.dart';
import '../deadline_settings/deadline_settings_screen.dart';
import '../report_email_settings/report_email_settings_screen.dart';
import '../category_priority_settings/category_priority_settings_screen.dart';
import '../original_content/original_content_screen.dart';
import '../../paywall/module_selection_screen.dart';
import '../employee_detail/employee_detail_screen.dart';
import '../team_comparison/team_comparison_screen.dart';
import '../../../widgets/error_retry_view.dart';
import '../../../widgets/skeleton_loader.dart';

/// 個人別一覧の部署フィルタで「全部署」を表す値(チームIDと衝突しないよう専用の値を使う)
const String _kAllTeamsFilter = '__all__';

/// 個人別一覧の並び替え条件
enum _EmployeeSortOption {
  nameAsc('氏名順'),
  progressDesc('進捗率が高い順'),
  progressAsc('進捗率が低い順');

  final String label;
  const _EmployeeSortOption(this.label);
}

/// 履修状況ダッシュボード(チーム別・個人別)。設計書 Must③。
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  // 業種のモジュール総数はほぼ不変のため、enrollments/employeesのライブ更新のたびに
  // 再取得してダッシュボード全体がスケルトンに戻る(ちらつく)ことがないよう一度だけ取得する。
  late final Future<int> _totalModulesFuture;
  // チーム一覧も同様に不変性が高いため一度だけ取得する(team_comparison_screenと同じ方針)。
  late final Future<List<Team>> _teamsFuture;

  String _selectedTeamId = _kAllTeamsFilter;
  _EmployeeSortOption _sortOption = _EmployeeSortOption.nameAsc;

  @override
  void initState() {
    super.initState();
    final company = ref.read(sessionProvider).company!;
    _totalModulesFuture = ref
        .read(contentServiceProvider)
        .getIndustry(company.industryId)
        .then((industry) async {
      if (industry == null) return 0;
      final modules =
          await ref.read(contentServiceProvider).listModulesForIndustry(industry);
      final customModules =
          await ref.read(customContentServiceProvider).listCustomModules(company.id);
      return modules.length + customModules.length;
    });
    _teamsFuture = ref
        .read(firestoreProvider)
        .collection('companies/${company.id}/teams')
        .get()
        .then((snap) => snap.docs.map((d) => Team.fromMap(d.id, d.data())).toList());
  }

  /// 部署フィルタ・並び替えを適用した個人別一覧を返す。
  List<EmployeeCompletionStat> _applyFilterAndSort(
    List<EmployeeCompletionStat> stats,
    Map<String, String> employeeTeamId,
  ) {
    var filtered = _selectedTeamId == _kAllTeamsFilter
        ? stats
        : stats
            .where((s) => (employeeTeamId[s.employeeId] ?? '') == _selectedTeamId)
            .toList();

    filtered = List<EmployeeCompletionStat>.from(filtered);

    switch (_sortOption) {
      case _EmployeeSortOption.nameAsc:
        filtered.sort((a, b) => a.displayName.compareTo(b.displayName));
        break;
      case _EmployeeSortOption.progressDesc:
        filtered.sort(
            (a, b) => b.completionRatePercent.compareTo(a.completionRatePercent));
        break;
      case _EmployeeSortOption.progressAsc:
        filtered.sort(
            (a, b) => a.completionRatePercent.compareTo(b.completionRatePercent));
        break;
    }

    return filtered;
  }

  /// 従業員進捗の内訳(修了/進行中/未着手)を円グラフで可視化
  Widget _buildProgressChartSection(
    ColorScheme colorScheme,
    List<EmployeeCompletionStat> stats,
  ) {
    final total = stats.length;
    if (total == 0) {
      return const SizedBox.shrink();
    }

    final completed = stats
        .where((s) => s.totalModuleCount > 0 && s.completedCount >= s.totalModuleCount)
        .length;
    final notStarted = stats.where((s) => s.completedCount == 0).length;
    final inProgress = total - completed - notStarted;

    final sections = <PieChartSectionData>[
      if (completed > 0)
        PieChartSectionData(
          value: completed.toDouble(),
          color: Colors.green,
          title: '$completed',
          radius: 52,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      if (inProgress > 0)
        PieChartSectionData(
          value: inProgress.toDouble(),
          color: Colors.orange,
          title: '$inProgress',
          radius: 52,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      if (notStarted > 0)
        PieChartSectionData(
          value: notStarted.toDouble(),
          color: Colors.grey,
          title: '$notStarted',
          radius: 52,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '進捗内訳',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sections: sections,
                        sectionsSpace: 2,
                        centerSpaceRadius: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildChartLegendRow(Colors.green, '修了', completed),
                        const SizedBox(height: 8),
                        _buildChartLegendRow(Colors.orange, '進行中', inProgress),
                        const SizedBox(height: 8),
                        _buildChartLegendRow(Colors.grey, '未着手', notStarted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartLegendRow(Color color, String label, int count) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text(
          '$count名',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// 個人別一覧の部署フィルタ・並び替えバー
  Widget _buildFilterSortBar(List<Team> teams) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildDropdownField<String>(
            label: '部署',
            value: _selectedTeamId,
            items: [
              const DropdownMenuItem(
                value: _kAllTeamsFilter,
                child: Text('全部署'),
              ),
              ...teams.map(
                (team) => DropdownMenuItem(
                  value: team.id,
                  child: Text(team.teamName, overflow: TextOverflow.ellipsis),
                ),
              ),
              const DropdownMenuItem(
                value: '',
                child: Text('未所属'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedTeamId = value);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDropdownField<_EmployeeSortOption>(
            label: '並び替え',
            value: _sortOption,
            items: _EmployeeSortOption.values
                .map(
                  (option) => DropdownMenuItem(
                    value: option,
                    child: Text(option.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _sortOption = value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[400]!),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.isSignedIn) {
      return const Scaffold(body: Center(child: Text('セッションが見つかりません')));
    }
    final company = session.company!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('履修状況ダッシュボード'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active),
            tooltip: '個別リマインド送信',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReminderScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'レポート出力',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportExportScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'チーム別受講率比較',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TeamComparisonScreen()),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '受講設定',
            onSelected: (value) {
              if (value == 'pass_threshold') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PassThresholdSettingsScreen()),
                );
              } else if (value == 'deadline') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeadlineSettingsScreen()),
                );
              } else if (value == 'report_email') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReportEmailSettingsScreen()),
                );
              } else if (value == 'category_priority') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CategoryPrioritySettingsScreen()),
                );
              } else if (value == 'original_content') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OriginalContentScreen()),
                );
              } else if (value == 'module_plan') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ModuleSelectionScreen()),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'module_plan', child: Text('受講プラン設定(基本/上位)')),
              PopupMenuItem(value: 'pass_threshold', child: Text('合格ライン設定')),
              PopupMenuItem(value: 'deadline', child: Text('受講期限設定')),
              PopupMenuItem(value: 'report_email', child: Text('月次レポート送付先設定')),
              PopupMenuItem(value: 'category_priority', child: Text('業種プロファイル調整')),
              PopupMenuItem(
                  value: 'original_content', child: Text('オリジナルコンテンツ管理(プレミアム)')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<Team>>(
        future: _teamsFuture,
        builder: (context, teamsSnapshot) {
          if (teamsSnapshot.hasError) {
            return const ErrorRetryView(message: 'チーム一覧の読み込みに失敗しました');
          }
          if (!teamsSnapshot.hasData) {
            return const SkeletonList();
          }
          final teams = teamsSnapshot.data!;

          return FutureBuilder<int>(
            future: _totalModulesFuture,
            builder: (context, totalModulesSnapshot) {
              if (totalModulesSnapshot.hasError) {
                return const ErrorRetryView(message: 'モジュール数の集計に失敗しました');
              }
              if (!totalModulesSnapshot.hasData) {
                return const SkeletonList();
              }
              final totalModules = totalModulesSnapshot.data!;

              return StreamBuilder<List<Employee>>(
            stream: ref.read(employeeServiceProvider).watchCompanyEmployees(company.id),
            builder: (context, employeeSnapshot) {
              if (employeeSnapshot.hasError) {
                return const ErrorRetryView(message: '社員一覧の読み込みに失敗しました');
              }
              if (!employeeSnapshot.hasData) {
                return const SkeletonList();
              }
              final employees = employeeSnapshot.data!;
              final employeeTeamId = {for (final e in employees) e.id: e.teamId};

              return StreamBuilder<List<Enrollment>>(
                stream:
                    ref.read(enrollmentServiceProvider).watchCompanyEnrollments(company.id),
                builder: (context, enrollmentSnapshot) {
                  if (enrollmentSnapshot.hasError) {
                    return const ErrorRetryView(message: '受講記録の読み込みに失敗しました');
                  }
                  if (!enrollmentSnapshot.hasData) {
                    return const SkeletonList();
                  }
                  final enrollments = enrollmentSnapshot.data!;

                  final stats = DashboardAnalytics.computeEmployeeCompletionStats(
                    employees: employees,
                    enrollments: enrollments,
                    totalModuleCount: totalModules,
                  );
                  final overall = DashboardAnalytics.overallCompletionRatePercent(stats);
                  final churnRisk = ChurnRisk.evaluate(
                    overallCompletionRatePercent: overall,
                    daysSinceCompanyCreated:
                        DateTime.now().difference(company.createdAt).inDays,
                  );
                  final visibleStats = _applyFilterAndSort(stats, employeeTeamId);

                  final colorScheme = Theme.of(context).colorScheme;
                  return Column(
                    children: [
                      Card(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.groups, color: colorScheme.primary),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '全社受講率',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    '$overall%',
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (churnRisk != ChurnRiskLevel.low)
                        Card(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                          color: churnRisk == ChurnRiskLevel.high
                              ? colorScheme.errorContainer
                              : colorScheme.tertiaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  color: churnRisk == ChurnRiskLevel.high
                                      ? colorScheme.onErrorContainer
                                      : colorScheme.onTertiaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '受講率が低下しています。個別リマインド送信をご検討ください',
                                    style: TextStyle(
                                      color: churnRisk == ChurnRiskLevel.high
                                          ? colorScheme.onErrorContainer
                                          : colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      _buildProgressChartSection(colorScheme, stats),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: _buildFilterSortBar(teams),
                      ),
                      Expanded(
                        child: visibleStats.isEmpty
                            ? const Center(child: Text('該当する社員がいません'))
                            : ListView.builder(
                          itemCount: visibleStats.length,
                          itemBuilder: (context, index) {
                            final stat = visibleStats[index];
                            final employee =
                                employees.firstWhere((e) => e.id == stat.employeeId);
                            return Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EmployeeDetailScreen(employee: employee),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              stat.displayName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: stat.completionRatePercent / 100,
                                                minHeight: 6,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${stat.completionRatePercent}%',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.chevron_right, color: colorScheme.outline),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      );
            },
          ),
        );
  }
}

