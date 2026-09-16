import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/service_providers.dart';
import '../../providers/session_provider.dart';
import '../industry_selection/industry_selection_screen.dart';
import '../dashboard/app_shell.dart';
import '../admin/company_profile/company_profile_screen.dart';

/// Aha Moment動線の入口: チームID(招待コード)入力 or 個人登録
class InviteEntryScreen extends ConsumerStatefulWidget {
  const InviteEntryScreen({super.key});

  @override
  ConsumerState<InviteEntryScreen> createState() => _InviteEntryScreenState();
}

class _InviteEntryScreenState extends ConsumerState<InviteEntryScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _joinWithInviteCode() async {
    final code = _codeController.text.trim();
    final displayName = _nameController.text.trim();
    if (code.isEmpty || displayName.isEmpty) {
      setState(() => _errorMessage = 'チームIDとお名前を入力してください');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final inviteService = ref.read(inviteServiceProvider);
      final invite = await inviteService.resolveInviteCode(code);
      if (invite == null || !invite.isValidNow(DateTime.now())) {
        setState(() {
          _errorMessage = 'チームIDが正しくないか、有効期限が切れています';
          _isLoading = false;
        });
        return;
      }

      final companyService = ref.read(companyServiceProvider);
      final company = await companyService.getCompany(invite.companyId);
      if (company == null) {
        setState(() {
          _errorMessage = '会社情報が見つかりませんでした';
          _isLoading = false;
        });
        return;
      }

      final employeeService = ref.read(employeeServiceProvider);
      final employee = await employeeService.joinViaInviteCode(
        companyId: invite.companyId,
        teamId: invite.teamId,
        displayName: displayName,
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
        // プッシュ通知トークン登録の失敗はサインイン自体を妨げない
        // (Firebase未設定環境や通知権限拒否時など)。
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    } catch (e) {
      setState(() {
        _errorMessage = '参加処理に失敗しました。時間をおいて再度お試しください';
        _isLoading = false;
      });
    }
  }

  void _startIndividual() {
    final displayName = _nameController.text.trim();
    if (displayName.isEmpty) {
      setState(() => _errorMessage = 'お名前を入力してください');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IndustrySelectionScreen(individualDisplayName: displayName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('安心企業研修Safy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Icon(Icons.shield_outlined, size: 56, color: colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'まずはお名前を教えてください',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: '例）山田 太郎'),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.groups_outlined, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'チームID(招待コード)をお持ちの方',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(hintText: '例）AB3D9F2K'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _joinWithInviteCode,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('チームIDで参加する'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_outline, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        '個人でお使いの方',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _startIndividual,
                      child: const Text('個人で始める'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.admin_panel_settings_outlined,
                          color: colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        '総務・人事・経営者の方（初回登録）',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CompanyProfileScreen(),
                                ),
                              ),
                      child: const Text('会社を新規登録する（管理者）'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
