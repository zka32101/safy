import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/company_model.dart';
import '../../providers/industry_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/session_provider.dart';
import '../dashboard/app_shell.dart';

/// 個人登録者向けの業種選択画面(チーム参加者は会社側で選択済みのためスキップ)
class IndustrySelectionScreen extends ConsumerStatefulWidget {
  final String individualDisplayName;

  const IndustrySelectionScreen({super.key, required this.individualDisplayName});

  @override
  ConsumerState<IndustrySelectionScreen> createState() =>
      _IndustrySelectionScreenState();
}

class _IndustrySelectionScreenState
    extends ConsumerState<IndustrySelectionScreen> {
  bool _isCreating = false;

  Future<void> _selectIndustry(String industryId) async {
    setState(() => _isCreating = true);
    try {
      final companyService = ref.read(companyServiceProvider);
      final employeeService = ref.read(employeeServiceProvider);

      final company = await companyService.createCompany(
        name: '${widget.individualDisplayName}様（個人）',
        industryId: industryId,
        planType: PlanType.individual,
        contractedHeadcount: 1,
      );
      final employee = await employeeService.createAdmin(
        companyId: company.id,
        teamId: '',
        displayName: widget.individualDisplayName,
      );

      ref.read(sessionProvider.notifier).signIn(
            employee: employee,
            company: company,
          );

      try {
        await ref.read(pushNotificationServiceProvider).registerToken(
              companyId: company.id,
              employeeId: employee.id,
            );
      } catch (_) {
        // プッシュ通知トークン登録の失敗はサインイン自体を妨げない。
      }

      if (!mounted) return;
      // InviteEntryScreenまで含めて戻れないようにする(戻ると別アカウントで再登録できてしまうため)。
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登録に失敗しました。時間をおいて再度お試しください')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final industriesAsync = ref.watch(industryListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('業種を選択してください')),
      body: _isCreating
          ? const Center(child: CircularProgressIndicator())
          : industriesAsync.when(
              data: (industries) => ListView.builder(
                itemCount: industries.length,
                itemBuilder: (context, index) {
                  final industry = industries[index];
                  return ListTile(
                    title: Text(industry.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _selectIndustry(industry.id),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('読み込みに失敗しました: $err')),
            ),
    );
  }
}
