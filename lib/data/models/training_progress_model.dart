/// Tier 1 Training の学習進捗モデル
class TrainingProgress {
  final String employeeId;
  final String companyId;
  final String moduleId;
  final int lessonsCompleted; // 0-4
  final int quizAttempts;
  final int maxScore; // 最高スコア（80以上で修了）
  final bool isPassed; // 80%以上で true
  final DateTime? completedAt;
  final DateTime? certificateIssuedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TrainingProgress({
    required this.employeeId,
    required this.companyId,
    required this.moduleId,
    required this.lessonsCompleted,
    required this.quizAttempts,
    required this.maxScore,
    required this.isPassed,
    this.completedAt,
    this.certificateIssuedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TrainingProgress.fromMap(Map<String, dynamic> map) {
    return TrainingProgress(
      employeeId: map['employeeId'] as String? ?? '',
      companyId: map['companyId'] as String? ?? '',
      moduleId: map['moduleId'] as String? ?? '',
      lessonsCompleted: (map['lessonsCompleted'] as num?)?.toInt() ?? 0,
      quizAttempts: (map['quizAttempts'] as num?)?.toInt() ?? 0,
      maxScore: (map['maxScore'] as num?)?.toInt() ?? 0,
      isPassed: map['isPassed'] as bool? ?? false,
      completedAt: map['completedAt'] != null
          ? _parseDateTime(map['completedAt'])
          : null,
      certificateIssuedAt: map['certificateIssuedAt'] != null
          ? _parseDateTime(map['certificateIssuedAt'])
          : null,
      createdAt: map['createdAt'] != null
          ? _parseDateTime(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? _parseDateTime(map['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
        'moduleId': moduleId,
        'lessonsCompleted': lessonsCompleted,
        'quizAttempts': quizAttempts,
        'maxScore': maxScore,
        'isPassed': isPassed,
        'completedAt': completedAt?.toIso8601String(),
        'certificateIssuedAt': certificateIssuedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static DateTime _parseDateTime(dynamic value) {
    if (value is String) {
      return DateTime.parse(value);
    } else if (value is DateTime) {
      return value;
    } else if (value.runtimeType.toString().contains('Timestamp')) {
      return (value as dynamic).toDate();
    }
    return DateTime.now();
  }

  TrainingProgress copyWith({
    String? employeeId,
    String? companyId,
    String? moduleId,
    int? lessonsCompleted,
    int? quizAttempts,
    int? maxScore,
    bool? isPassed,
    DateTime? completedAt,
    DateTime? certificateIssuedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TrainingProgress(
      employeeId: employeeId ?? this.employeeId,
      companyId: companyId ?? this.companyId,
      moduleId: moduleId ?? this.moduleId,
      lessonsCompleted: lessonsCompleted ?? this.lessonsCompleted,
      quizAttempts: quizAttempts ?? this.quizAttempts,
      maxScore: maxScore ?? this.maxScore,
      isPassed: isPassed ?? this.isPassed,
      completedAt: completedAt ?? this.completedAt,
      certificateIssuedAt: certificateIssuedAt ?? this.certificateIssuedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Training Certificate: 修了証
class TrainingCertificate {
  final String id;
  final String employeeId;
  final String companyId;
  final List<String> completedModuleIds; // 修了した4モジュールID
  final DateTime issuedAt;
  final DateTime validUntil; // 有効期限（1年）
  final String certificateNumber; // CERT-202609-XXXX 形式

  const TrainingCertificate({
    required this.id,
    required this.employeeId,
    required this.companyId,
    required this.completedModuleIds,
    required this.issuedAt,
    required this.validUntil,
    required this.certificateNumber,
  });

  factory TrainingCertificate.fromMap(String id, Map<String, dynamic> map) {
    return TrainingCertificate(
      id: id,
      employeeId: map['employeeId'] as String? ?? '',
      companyId: map['companyId'] as String? ?? '',
      completedModuleIds:
          List<String>.from(map['completedModuleIds'] as List? ?? []),
      issuedAt: map['issuedAt'] != null
          ? DateTime.parse(map['issuedAt'] as String)
          : DateTime.now(),
      validUntil: map['validUntil'] != null
          ? DateTime.parse(map['validUntil'] as String)
          : DateTime.now().add(const Duration(days: 365)),
      certificateNumber: map['certificateNumber'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
        'completedModuleIds': completedModuleIds,
        'issuedAt': issuedAt.toIso8601String(),
        'validUntil': validUntil.toIso8601String(),
        'certificateNumber': certificateNumber,
      };
}

/// モジュール単位の学習進捗集計（進捗分析ダッシュボード用）
///
/// [TrainingProgress] のリストから、モジュールごとの完了率・平均スコア・
/// 平均学習時間などを集計する。Firestore/Riverpodに依存しない純粋なロジックなので
/// ユニットテストで検証しやすい。
class ModuleProgressStat {
  final String moduleId;
  final int recordCount; // このモジュールの学習記録件数
  final int passedCount; // 合格(80%以上)件数
  final double completionRate; // 0.0〜1.0（記録に対する合格の割合）
  final double averageScore; // 平均最高スコア
  final double averageQuizAttempts; // 平均クイズ受験回数
  final Duration averageStudyDuration; // 学習開始(createdAt)〜完了/最終更新までの目安時間

  const ModuleProgressStat({
    required this.moduleId,
    required this.recordCount,
    required this.passedCount,
    required this.completionRate,
    required this.averageScore,
    required this.averageQuizAttempts,
    required this.averageStudyDuration,
  });

  factory ModuleProgressStat.fromRecords(
    String moduleId,
    List<TrainingProgress> allProgress,
  ) {
    final records = allProgress.where((p) => p.moduleId == moduleId).toList();

    if (records.isEmpty) {
      return ModuleProgressStat(
        moduleId: moduleId,
        recordCount: 0,
        passedCount: 0,
        completionRate: 0,
        averageScore: 0,
        averageQuizAttempts: 0,
        averageStudyDuration: Duration.zero,
      );
    }

    final passedCount = records.where((p) => p.isPassed).length;
    final totalScore = records.fold<int>(0, (sum, p) => sum + p.maxScore);
    final totalQuizAttempts =
        records.fold<int>(0, (sum, p) => sum + p.quizAttempts);
    final totalStudyMinutes = records.fold<int>(0, (sum, p) {
      final end = p.completedAt ?? p.updatedAt;
      final diff = end.difference(p.createdAt);
      return sum + (diff.isNegative ? 0 : diff.inMinutes);
    });

    return ModuleProgressStat(
      moduleId: moduleId,
      recordCount: records.length,
      passedCount: passedCount,
      completionRate: passedCount / records.length,
      averageScore: totalScore / records.length,
      averageQuizAttempts: totalQuizAttempts / records.length,
      averageStudyDuration:
          Duration(minutes: (totalStudyMinutes / records.length).round()),
    );
  }
}

/// 期間内の1日ごとの修了件数（進捗推移グラフ用）
class DailyProgressPoint {
  final DateTime date;
  final int completedCount;

  const DailyProgressPoint({
    required this.date,
    required this.completedCount,
  });
}

/// 進捗分析ダッシュボード・レポート画面向けの集計結果一式
///
/// 個人（対象社員1名分の[TrainingProgress]のみ）にも、チーム/会社全体
/// （複数社員分の[TrainingProgress]をまとめたもの）にも同じロジックで使える。
class TrainingProgressReport {
  final List<ModuleProgressStat> moduleStats;
  final int totalModules;
  final int completedModules; // isPassed済みのユニークモジュール数
  final double overallCompletionRate; // 0.0〜1.0
  final double overallAverageScore;
  final int totalQuizAttempts;
  final List<DailyProgressPoint> dailyTrend;

  const TrainingProgressReport({
    required this.moduleStats,
    required this.totalModules,
    required this.completedModules,
    required this.overallCompletionRate,
    required this.overallAverageScore,
    required this.totalQuizAttempts,
    required this.dailyTrend,
  });

  factory TrainingProgressReport.build({
    required List<String> moduleIds,
    required List<TrainingProgress> progress,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    final moduleStats = moduleIds
        .map((id) => ModuleProgressStat.fromRecords(id, progress))
        .toList();

    final completedModuleIds =
        progress.where((p) => p.isPassed).map((p) => p.moduleId).toSet();

    final scores = progress.map((p) => p.maxScore).toList();
    final overallAverageScore =
        scores.isEmpty ? 0.0 : scores.reduce((a, b) => a + b) / scores.length;

    final totalQuizAttempts =
        progress.fold<int>(0, (sum, p) => sum + p.quizAttempts);

    final normalizedStart =
        DateTime(periodStart.year, periodStart.month, periodStart.day);
    final normalizedEnd =
        DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
    final dayCount = normalizedEnd.difference(normalizedStart).inDays + 1;

    final dailyTrend = <DailyProgressPoint>[];
    for (var i = 0; i < dayCount; i++) {
      final day = normalizedStart.add(Duration(days: i));
      final nextDay = day.add(const Duration(days: 1));
      final count = progress.where((p) {
        final completedAt = p.completedAt;
        if (completedAt == null) return false;
        return !completedAt.isBefore(day) && completedAt.isBefore(nextDay);
      }).length;
      dailyTrend.add(DailyProgressPoint(date: day, completedCount: count));
    }

    return TrainingProgressReport(
      moduleStats: moduleStats,
      totalModules: moduleIds.length,
      completedModules: completedModuleIds.length,
      overallCompletionRate: moduleIds.isEmpty
          ? 0
          : completedModuleIds.length / moduleIds.length,
      overallAverageScore: overallAverageScore,
      totalQuizAttempts: totalQuizAttempts,
      dailyTrend: dailyTrend,
    );
  }
}
