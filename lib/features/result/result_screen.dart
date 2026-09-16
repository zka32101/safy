import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/module_model.dart';
import '../../data/models/quiz_attempt_model.dart';
import '../../providers/service_providers.dart';
import '../../providers/session_provider.dart';
import '../dashboard/app_shell.dart';
import '../lesson/lesson_screen.dart';
import '../../widgets/success_checkmark.dart';

/// 結果画面: 合格→修了証／不合格→説明ページに戻り再受講(懲罰的演出は禁止・前向きな文言で誘導)
class ResultScreen extends ConsumerWidget {
  final Module module;
  final QuizAttempt attempt;

  const ResultScreen({super.key, required this.module, required this.attempt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              attempt.passed
                  ? const SuccessCheckmark()
                  : Icon(
                      Icons.refresh,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              const SizedBox(height: 16),
              Text(
                attempt.passed ? '修了おめでとうございます！' : 'あと少しで合格です！',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text('スコア: ${attempt.score}点（合格ライン: ${attempt.thresholdApplied}点）'),
              const SizedBox(height: 32),
              if (attempt.passed)
                FilledButton(
                  onPressed: () async {
                    final session = ref.read(sessionProvider);
                    if (session.isSignedIn) {
                      await ref.read(enrollmentServiceProvider).completeModuleForEmployee(
                            companyId: session.company!.id,
                            employeeId: session.employee!.id,
                            moduleId: module.id,
                          );
                      await ref.read(analyticsServiceProvider).logModuleCompleted(
                            companyId: session.company!.id,
                            moduleId: module.id,
                            score: attempt.score,
                          );
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const AppShell()),
                      (route) => false,
                    );
                  },
                  child: const Text('ホームに戻る'),
                )
              else
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => LessonScreen(module: module),
                      ),
                    );
                  },
                  child: const Text('説明ページを見直してもう一度挑戦する'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
