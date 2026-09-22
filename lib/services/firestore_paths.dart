/// Firestoreコレクションパスの単一ソース。
/// マルチテナントデータ(Company配下)とグローバルコンテンツ(業種/モジュール等)を明確に分離する。
/// 他ファイルでパス文字列を直接書かず、必ずここを経由すること。
class FirestorePaths {
  FirestorePaths._();

  // --- マルチテナント（企業単位で分離必須） ---
  static String company(String companyId) => 'companies/$companyId';
  static String teams(String companyId) => '${company(companyId)}/teams';
  static String team(String companyId, String teamId) =>
      '${teams(companyId)}/$teamId';
  static String employees(String companyId) =>
      '${company(companyId)}/employees';
  static String employee(String companyId, String employeeId) =>
      '${employees(companyId)}/$employeeId';
  static String enrollments(String companyId) =>
      '${company(companyId)}/enrollments';
  static String progressRecords(String companyId) =>
      '${company(companyId)}/progressRecords';
  static String quizAttempts(String companyId) =>
      '${company(companyId)}/quizAttempts';
  static String certificates(String companyId) =>
      '${company(companyId)}/certificates';
  static String subscriptions(String companyId) =>
      '${company(companyId)}/subscriptions';
  static String reminders(String companyId) =>
      '${company(companyId)}/reminders';
  static String examAttempts(String companyId) =>
      '${company(companyId)}/examAttempts';
  static String examAttempt(String companyId, String examAttemptId) =>
      '${examAttempts(companyId)}/$examAttemptId';

  // --- オリジナルコンテンツ(プレミアムプラン。会社単位で完全に分離) ---
  /// 新規オリジナルモジュール一式(モジュール本体はここに保存。中身はグローバルmodulesと同じ形)
  static String customModules(String companyId) =>
      '${company(companyId)}/customModules';
  static String customModule(String companyId, String moduleId) =>
      '${customModules(companyId)}/$moduleId';
  static String customModuleLessons(String companyId, String moduleId) =>
      '${customModule(companyId, moduleId)}/lessons';
  static String customModuleQuizQuestions(String companyId, String moduleId) =>
      '${customModule(companyId, moduleId)}/quizQuestions';

  /// 既存(グローバル)モジュールへの追加コンテンツ。moduleIdはmodules/{moduleId}を指す。
  static String moduleExtensions(String companyId) =>
      '${company(companyId)}/moduleExtensions';
  static String moduleExtension(String companyId, String moduleId) =>
      '${moduleExtensions(companyId)}/$moduleId';
  static String moduleExtensionLessons(String companyId, String moduleId) =>
      '${moduleExtension(companyId, moduleId)}/lessons';
  static String moduleExtensionQuizQuestions(String companyId, String moduleId) =>
      '${moduleExtension(companyId, moduleId)}/quizQuestions';

  // --- 招待コード（Join前はテナント文脈が無いためトップレベル） ---
  static const String inviteCodes = 'inviteCodes';

  // --- ライブ認定試験（グローバルコンテンツ。受験結果はテナント配下のexamAttemptsへ） ---
  static const String exams = 'exams';
  static String examQuestions(String examId) => '$exams/$examId/questions';

  // --- グローバルコンテンツ（全テナント共通・読み取り専用） ---
  static const String industries = 'industries';
  static const String modules = 'modules';
  static String lessons(String moduleId) => 'modules/$moduleId/lessons';
  static String quizQuestions(String moduleId) =>
      'modules/$moduleId/quizQuestions';

  // --- Q&Aフォーラム（企業単位で分離） ---
  static String qaForum(String companyId) =>
      '${company(companyId)}/qaForum';
  static String qaQuestion(String companyId, String questionId) =>
      '${qaForum(companyId)}/$questionId';
  static String qaAnswers(String companyId, String questionId) =>
      '${qaQuestion(companyId, questionId)}/answers';
  static String qaAnswer(
          String companyId, String questionId, String answerId) =>
      '${qaAnswers(companyId, questionId)}/$answerId';
}
