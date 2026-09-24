import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/my_growth_provider.dart';
import '../../data/models/category_model.dart';
import '../../widgets/category_badge.dart';
import '../../core/review_recommender.dart';

/// マイ成長画面: 6カテゴリのレーダーチャート(設計書Step3.5/Section2 Should機能)
class MyGrowthScreen extends ConsumerWidget {
  const MyGrowthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radarAsync = ref.watch(myGrowthRadarProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('成長')),
      body: radarAsync.when(
        data: (scores) {
          if (scores.isEmpty) {
            return const Center(child: Text('まだ受講記録がありません'));
          }
          final reviewTargets = ReviewRecommender.recommendForReview(scores);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: RadarChart(
                  RadarChartData(
                    radarShape: RadarShape.polygon,
                    dataSets: [
                      RadarDataSet(
                        dataEntries: scores
                            .map((s) => RadarEntry(value: s.averageScore.toDouble()))
                            .toList(),
                        fillColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.2),
                        borderColor: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                    getTitle: (index, angle) {
                      final category = Category.byId(scores[index].categoryId);
                      return RadarChartTitle(text: category.name);
                    },
                    tickCount: 5,
                    ticksTextStyle: const TextStyle(fontSize: 0),
                    radarBorderData: const BorderSide(color: Colors.transparent),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: scores
                    .map((s) => CategoryBadge(
                          categoryId: s.categoryId,
                          earned: s.attemptCount > 0,
                        ))
                    .toList(),
              ),
              if (reviewTargets.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text('復習をおすすめします', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...reviewTargets.map((s) => ListTile(
                      leading: const Icon(Icons.refresh),
                      title: Text(Category.byId(s.categoryId).name),
                      subtitle: Text('平均正答率 ${s.averageScore}%'),
                    )),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('読み込みに失敗しました: $err')),
      ),
    );
  }
}
