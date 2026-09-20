import 'package:flutter/material.dart';
import '../generated/app_localizations.dart';

/// Extension to easily access localized strings from BuildContext
extension LocalizationsExt on BuildContext {
  AppLocalizations get l10n {
    return AppLocalizations.of(this)!;
  }
}

/// Extension to easily access localized strings from AppLocalizations
extension AppLocalizationsExt on AppLocalizations {
  /// Module name localization helper
  String getModuleName(String moduleId) {
    switch (moduleId) {
      case 'm_ethics_sns':
        return module_sns;
      case 'm_ethics_harassment':
        return module_harassment;
      case 'm_security_basics':
      case 'm_security_phishing':
        return module_security;
      case 'm_phishing':
        return module_phishing;
      case 'm_privacy_basics':
        return module_privacy;
      case 'm_compliance_basics':
        return module_compliance;
      case 'm_ai_basics':
      case 'm_ai_ethics':
      case 'm_ai_customer':
      case 'm_ai_data':
        return module_ai;
      case 'm_ai_deepfake':
        return module_deepfake;
      case 'm_mental_selfcare':
        return module_mental;
      case 'm_bcp_basics':
        return module_bcp;
      case 'm_sustainability_sdgs':
        return module_sdgs;
      default:
        return moduleId;
    }
  }

  /// Error message localization helper
  String getErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'network_error':
        return error_networkError;
      case 'server_error':
        return error_serverError;
      case 'timeout_error':
        return error_timeoutError;
      case 'not_found':
        return error_notFound;
      case 'unauthorized':
        return error_unauthorized;
      default:
        return common_error;
    }
  }
}
