import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../../providers/session_provider.dart';
import '../../widgets/error_retry_view.dart';
import 'employee_detail_screen.dart';

/// 企業別ダッシュボード：HR/マネージャー向けの進捗・実績管理画面
class CompanyDashboardScreen extends ConsumerStatefulWidget {
  const CompanyDashboardScreen({super.key});

  @override
  ConsumerState<CompanyDashboardScreen> createState() =>
      _CompanyDashboardScreenState();
}

class _CompanyDashboardScreenState
    extends ConsumerState<CompanyDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return session.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => ErrorRetryView(
        error: err.toString(),
        onRetry: () => ref.refresh(sessionProvider),
      ),
      data: (sessionData) {
        if (sessionData == null || !sessionData.isAdmin) {
          return const Center(
            child: Text('管理者権限が必要です'),
          );
        }

        return _buildDashboard(context, sessionData.companyId);
      },
    );
  }

  Widget _buildDashboard(BuildContext context, String companyId) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('企業ダッシュボード'),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (String value) async {
              if (value == 'export_csv') {
                _exportToCSV(context, companyId);
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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
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
              error: snapshot.error.toString(),
              onRetry: () => setState(() {}),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final stats = _calculateStats(docs);

          return SingleChildScrollView(
            child: Column(
              children: [
                _buildSummarySection(context, stats),
                _buildModuleProgressSection(context, stats),
                _buildEmployeeListSection(context, stats),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  CompanyStats _calculateStats(List<QueryDocumentSnapshot> docs) {
    final employeeProgress = <String, EmployeeStats>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final employeeId = data['employeeId'] as String;
      final moduleId = data['moduleId'] as String;
      final isPassed = data['passed'] as bool? ?? false;

      if (!employeeProgress.containsKey(employeeId)) {
        employeeProgress[employeeId] = EmployeeStats(employeeId: employeeId);
      }

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

  Widget _buildEmployeeListSection(BuildContext context, CompanyStats stats) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '従業員一覧',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: stats.employeeStats.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: Colors.grey[300],
              ),
              itemBuilder: (context, index) {
                final employee = stats.employeeStats[index];
                final completionPercent =
                    (employee.completedModules.length / 4 * 100).toInt();

                return InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => EmployeeDetailScreen(
                          companyId: companyId,
                          employeeId: employee.employeeId,
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
                                employee.employeeId,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
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

  Future<void> _exportToCSV(BuildContext context, String companyId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('trainingAttempts')
          .get();

      final docs = snapshot.docs;
      final stats = _calculateStats(docs);

      final csvRows = <List<String>>[];
      csvRows.add([
        '従業員ID',
        'Platform技術',
        'Operations',
        'Content Production',
        'GTM Strategy',
        '修了モジュール数',
        '完了率',
      ]);

      for (final employee in stats.employeeStats) {
        final completionPercent =
            (employee.completedModules.length / 4 * 100).toInt();
        csvRows.add([
          employee.employeeId,
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
          text: '${stats.totalEmployees}名の研修進捗レポートです。全体修了率: ${stats.completionRate.toStringAsFixed(1)}%',
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
  final Set<String> completedModules;

  EmployeeStats({
    required this.employeeId,
    Set<String>? completedModules,
  }) : completedModules = completedModules ?? {};
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
