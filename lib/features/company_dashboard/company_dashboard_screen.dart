import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/firebase_providers.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/team_model.dart';
import '../../widgets/error_retry_view.dart';
import 'employee_detail_screen.dart';

/// 従業員一覧の並び替え条件
enum EmployeeSortOption {
  nameAsc('氏名順'),
  progressDesc('進捗率が高い順'),
  progressAsc('進捗率が低い順');

  final String label;
  const EmployeeSortOption(this.label);
}

/// 部署フィルタで「全部署」を表す値（チームIDと衝突しないよう専用の値を使う）
const String _kAllTeamsFilter = '__all__';

/// 企業別ダッシュボード：HR/マネージャー向けの進捗・実績管理画面
class CompanyDashboardScreen extends ConsumerStatefulWidget {
  const CompanyDashboardScreen({super.key});

  @override
  ConsumerState<CompanyDashboardScreen> createState() =>
      _CompanyDashboardScreenState();
}

class _CompanyDashboardScreenState
    extends ConsumerState<CompanyDashboardScreen> {
  late final Future<List<Team>> _teamsFuture;

  String _selectedTeamId = _kAllTeamsFilter;
  EmployeeSortOption _sortOption = EmployeeSortOption.nameAsc;

  // CSVエクスポートは現在画面に表示されている(フィルタ・ソート適用後の)一覧を
  // そのまま出力できるよう、直近のビルド結果を保持しておく。
  CompanyStats? _latestStats;
  List<EmployeeStats> _latestVisibleEmployees = [];

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    final companyId = session.company?.id;
    _teamsFuture = companyId == null
        ? Future.value(<Team>[])
        : ref
            .read(firestoreProvider)
            .collection('companies/$companyId/teams')
            .get()
            .then((snap) =>
                snap.docs.map((d) => Team.fromMap(d.id, d.data())).toList());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    if (!session.isSignedIn || session.company == null) {
      return const Scaffold(
        body: Center(child: Text('セッションが見つかりません')),
      );
    }

    if (!session.isAdmin) {
      return const Scaffold(
        body: Center(child: Text('管理者権限が必要です')),
      );
    }

    return _buildDashboard(context, session.company!.id);
  }

  Widget _buildDashboard(BuildContext context, String companyId) {
    final firestore = ref.watch(firestoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('企業ダッシュボード'),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (String value) async {
              if (value == 'export_csv') {
                _exportToCSV(context);
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'export_csv',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 20),
                    SizedBox(width: 12),
                    Text('CSVエクスポート'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<Team>>(
        future: _teamsFuture,
        builder: (context, teamsSnapshot) {
          if (teamsSnapshot.hasError) {
            return ErrorRetryView(
              message: 'チーム情報の読み込みに失敗しました: ${teamsSnapshot.error}',
              onRetry: () => setState(() {}),
            );
          }
          if (!teamsSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final teams = teamsSnapshot.data!;
          final teamNameById = {for (final t in teams) t.id: t.teamName};

          return StreamBuilder<QuerySnapshot>(
            stream: firestore
                .collection('companies')
                .doc(companyId)
                .collection('employees')
                .snapshots(),
            builder: (context, employeeSnapshot) {
              if (employeeSnapshot.hasError) {
                return ErrorRetryView(
                  message: '従業員一覧の読み込みに失敗しました: ${employeeSnapshot.error}',
                  onRetry: () => setState(() {}),
                );
              }
              if (!employeeSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final employees = employeeSnapshot.data!.docs
                  .map((d) =>
                      Employee.fromMap(d.id, d.data() as Map<String, dynamic>))
                  .toList();

              return StreamBuilder<QuerySnapshot>(
                stream: firestore
                    .collection('companies')
                    .doc(companyId)
                    .collection('trainingAttempts')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return ErrorRetryView(
                      message: '研修進捗の読み込みに失敗しました: ${snapshot.error}',
                      onRetry: () => setState(() {}),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final stats =
                      _calculateStats(employees, docs, teamNameById);
                  final visibleEmployees =
                      _applyFilterAndSort(stats.employeeStats);

                  // 直近の表示内容をCSVエクスポート用に保持
                  _latestStats = stats;
                  _latestVisibleEmployees = visibleEmployees;

                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildSummarySection(context, stats),
                        _buildProgressChartSection(context, stats),
                        _buildModuleProgressSection(context, stats),
                        _buildEmployeeListSection(
                          context,
                          companyId,
                          teams,
                          visibleEmployees,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  CompanyStats _calculateStats(
    List<Employee> employees,
    List<QueryDocumentSnapshot> docs,
    Map<String, String> teamNameById,
  ) {
    final employeeProgress = <String, EmployeeStats>{};

    // まず在籍中の従業員を全員登録しておく(受講記録がまだ無い=未着手の従業員も一覧・
    // フィルタ対象に含めるため)
    for (final employee in employees) {
      employeeProgress[employee.id] = EmployeeStats(
        employeeId: employee.id,
        displayName:
            employee.displayName.isNotEmpty ? employee.displayName : employee.id,
        teamId: employee.teamId,
        teamName: employee.teamId.isEmpty
            ? '未所属'
            : (teamNameById[employee.teamId] ?? employee.teamId),
      );
    }

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final employeeId = data['employeeId'] as String;
      final moduleId = data['moduleId'] as String;
      final isPassed = data['passed'] as bool? ?? false;

      // 退職等で従業員マスタから削除済みでも、受講記録自体は一覧に反映する
      employeeProgress.putIfAbsent(
        employeeId,
        () => EmployeeStats(
          employeeId: employeeId,
          displayName: employeeId,
          teamId: '',
          teamName: '未所属',
        ),
      );

      if (isPassed) {
        employeeProgress[employeeId]!.completedModules.add(moduleId);
      }
    }

    // モジュール別統計
    final moduleStats = <String, ModuleStats>{};
    const modules = [
      'tier1-platform-tech',
      'tier1-operations',
      'tier1-content-production',
      'tier1-gtm-strategy',
    ];

    for (final module in modules) {
      final attempts = docs
          .where((doc) => (doc.data() as Map)['moduleId'] == module)
          .toList();
      final passed = attempts
          .where((doc) => (doc.data() as Map)['passed'] == true)
          .length;
      moduleStats[module] = ModuleStats(
        moduleId: module,
        totalAttempts: attempts.length,
        passedCount: passed,
        passRate:
            attempts.isNotEmpty ? (passed / attempts.length * 100) : 0,
      );
    }

    return CompanyStats(
      employeeStats: employeeProgress.values.toList(),
      moduleStats: moduleStats,
      totalEmployees: employeeProgress.length,
      completionRate: employeeProgress.isNotEmpty
          ? (employeeProgress.values
                  .where((e) => e.completedModules.length == 4)
                  .length /
              employeeProgress.length *
              100)
          : 0,
    );
  }

  List<EmployeeStats> _applyFilterAndSort(List<EmployeeStats> employeeStats) {
    var filtered = _selectedTeamId == _kAllTeamsFilter
        ? employeeStats
        : employeeStats
            .where((e) => e.teamId == _selectedTeamId)
            .toList();

    filtered = List<EmployeeStats>.from(filtered);

    switch (_sortOption) {
      case EmployeeSortOption.nameAsc:
        filtered.sort((a, b) => a.displayName.compareTo(b.displayName));
        break;
      case EmployeeSortOption.progressDesc:
        filtered.sort((a, b) =>
            b.completedModules.length.compareTo(a.completedModules.length));
        break;
      case EmployeeSortOption.progressAsc:
        filtered.sort((a, b) =>
            a.completedModules.length.compareTo(b.completedModules.length));
        break;
    }

    return filtered;
  }

  Widget _buildSummarySection(BuildContext context, CompanyStats stats) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '統計情報',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  title: '全体修了率',
                  value: '${stats.completionRate.toStringAsFixed(1)}%',
                  subtitle:
                      '${stats.totalEmployees} 名中 ${(stats.totalEmployees * stats.completionRate / 100).toStringAsFixed(0)} 名',
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  title: '対象者',
                  value: '${stats.totalEmployees}',
                  subtitle: '名',
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 従業員進捗の内訳(修了/進行中/未着手)を円グラフで可視化
  Widget _buildProgressChartSection(BuildContext context, CompanyStats stats) {
    final total = stats.employeeStats.length;
    if (total == 0) {
      return const SizedBox.shrink();
    }

    final completed =
        stats.employeeStats.where((e) => e.completedModules.length == 4).length;
    final inProgress = stats.employeeStats
        .where((e) =>
            e.completedModules.isNotEmpty && e.completedModules.length < 4)
        .length;
    final notStarted =
        stats.employeeStats.where((e) => e.completedModules.isEmpty).length;

    final sections = <PieChartSectionData>[
      if (completed > 0)
        PieChartSectionData(
          value: completed.toDouble(),
          color: Colors.green,
          title: '$completed',
          radius: 56,
          titleStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      if (inProgress > 0)
        PieChartSectionData(
          value: inProgress.toDouble(),
          color: Colors.orange,
          title: '$inProgress',
          radius: 56,
          titleStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      if (notStarted > 0)
        PieChartSectionData(
          value: notStarted.toDouble(),
          color: Colors.grey,
          title: '$notStarted',
          radius: 56,
          titleStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '進捗内訳',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              height: 160,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sections: sections,
                        sectionsSpace: 2,
                        centerSpaceRadius: 28,
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
                        _buildLegendRow(Colors.green, '修了 (4/4)', completed),
                        const SizedBox(height: 10),
                        _buildLegendRow(Colors.orange, '進行中', inProgress),
                        const SizedBox(height: 10),
                        _buildLegendRow(Colors.grey, '未着手', notStarted),
                      ],
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

  Widget _buildLegendRow(Color color, String label, int count) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Text(
          '$count名',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildModuleProgressSection(BuildContext context, CompanyStats stats) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'モジュール別進捗',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...stats.moduleStats.values.map((module) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildModuleProgressBar(context, module),
          )),
        ],
      ),
    );
  }

  Widget _buildModuleProgressBar(BuildContext context, ModuleStats module) {
    final moduleNames = {
      'tier1-platform-tech': 'Platform技術',
      'tier1-operations': 'Operations',
      'tier1-content-production': 'Content Production',
      'tier1-gtm-strategy': 'GTM Strategy',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              moduleNames[module.moduleId] ?? module.moduleId,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${module.passRate.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: module.passRate >= 70 ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: module.passRate / 100,
            minHeight: 8,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              module.passRate >= 70 ? Colors.green : Colors.orange,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${module.passedCount} / ${module.totalAttempts} 名',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeListSection(
    BuildContext context,
    String companyId,
    List<Team> teams,
    List<EmployeeStats> visibleEmployees,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '従業員一覧',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '該当 ${visibleEmployees.length} 名',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFilterSortBar(context, teams),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: visibleEmployees.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('該当する従業員がいません')),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: visibleEmployees.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: Colors.grey[300],
                    ),
                    itemBuilder: (context, index) {
                      final employee = visibleEmployees[index];
                      final completionPercent =
                          (employee.completedModules.length / 4 * 100).toInt();

                      return InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => EmployeeDetailScreen(
                                companyId: companyId,
                                employeeId: employee.employeeId,
                                employeeName: employee.displayName,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      employee.displayName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      employee.teamName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: completionPercent / 100,
                                        minHeight: 6,
                                        backgroundColor: Colors.grey[300],
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          completionPercent == 100
                                              ? Colors.green
                                              : Colors.blue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: completionPercent == 100
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${employee.completedModules.length}/4',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: completionPercent == 100
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSortBar(BuildContext context, List<Team> teams) {
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
                  child: Text(
                    team.teamName,
                    overflow: TextOverflow.ellipsis,
                  ),
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
          child: _buildDropdownField<EmployeeSortOption>(
            label: '並び替え',
            value: _sortOption,
            items: EmployeeSortOption.values
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

  Future<void> _exportToCSV(BuildContext context) async {
    final stats = _latestStats;
    if (stats == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('データの読み込みが完了してから再度お試しください')),
      );
      return;
    }

    try {
      // 現在フィルタ・ソートされて画面に表示されている従業員のみを出力する
      final targetEmployees = _latestVisibleEmployees;

      final csvRows = <List<String>>[];
      csvRows.add([
        '従業員ID',
        '氏名',
        '部署',
        'Platform技術',
        'Operations',
        'Content Production',
        'GTM Strategy',
        '修了モジュール数',
        '完了率',
      ]);

      for (final employee in targetEmployees) {
        final completionPercent =
            (employee.completedModules.length / 4 * 100).toInt();
        csvRows.add([
          employee.employeeId,
          employee.displayName,
          employee.teamName,
          employee.completedModules.contains('tier1-platform-tech') ? '✓' : '○',
          employee.completedModules.contains('tier1-operations') ? '✓' : '○',
          employee.completedModules.contains('tier1-content-production')
              ? '✓'
              : '○',
          employee.completedModules.contains('tier1-gtm-strategy') ? '✓' : '○',
          '${employee.completedModules.length}/4',
          '$completionPercent%',
        ]);
      }

      final csv = const ListToCsvConverter().convert(csvRows);
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file =
          File('${directory.path}/company_training_report_$timestamp.csv');
      await file.writeAsString(csv);

      if (context.mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: '企業研修進捗レポート',
          text:
              '${targetEmployees.length}名の研修進捗レポートです。全体修了率: ${stats.completionRate.toStringAsFixed(1)}%',
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エクスポートに失敗しました: $e')),
        );
      }
    }
  }
}

class CompanyStats {
  final List<EmployeeStats> employeeStats;
  final Map<String, ModuleStats> moduleStats;
  final int totalEmployees;
  final double completionRate;

  CompanyStats({
    required this.employeeStats,
    required this.moduleStats,
    required this.totalEmployees,
    required this.completionRate,
  });
}

class EmployeeStats {
  final String employeeId;
  final String displayName;
  final String teamId;
  final String teamName;
  final Set<String> completedModules;

  EmployeeStats({
    required this.employeeId,
    String? displayName,
    this.teamId = '',
    this.teamName = '未所属',
    Set<String>? completedModules,
  })  : displayName = displayName ?? employeeId,
        completedModules = completedModules ?? {};
}

class ModuleStats {
  final String moduleId;
  final int totalAttempts;
  final int passedCount;
  final double passRate;

  ModuleStats({
    required this.moduleId,
    required this.totalAttempts,
    required this.passedCount,
    required this.passRate,
  });
}
