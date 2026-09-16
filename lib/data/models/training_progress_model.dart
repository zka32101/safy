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
          ? DateTime.parse(map['completedAt'] as String)
          : null,
      certificateIssuedAt: map['certificateIssuedAt'] != null
          ? DateTime.parse(map['certificateIssuedAt'] as String)
          : null,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
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
