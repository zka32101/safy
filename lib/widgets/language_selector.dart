import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../extensions/localization_extension.dart';
import '../providers/localization_provider.dart';

/// Extension to get flag emoji for each locale
extension FlagEmojiExtension on SupportedLocale {
  String get flagEmoji {
    switch (this) {
      case SupportedLocale.ja:
        return '🇯🇵';
      case SupportedLocale.en:
        return '🇺🇸';
      case SupportedLocale.zh:
        return '🇨🇳';
      case SupportedLocale.ko:
        return '🇰🇷';
      case SupportedLocale.th:
        return '🇹🇭';
      case SupportedLocale.vi:
        return '🇻🇳';
      case SupportedLocale.id:
        return '🇮🇩';
      case SupportedLocale.tl:
        return '🇵🇭';
    }
  }
}

/// Widget to select and change app language
class LanguageSelector extends ConsumerWidget {
  final bool showTitle;

  const LanguageSelector({
    super.key,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(currentSupportedLocaleProvider);
    final localizationNotifier = ref.read(localizationProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Text(
              context.l10n.settings_language,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ...SupportedLocale.values.map((locale) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: LanguageTile(
              locale: locale,
              isSelected: currentLocale == locale,
              onTap: () {
                localizationNotifier.setLocaleFromEnum(locale);
              },
            ),
          );
        }).toList(),
      ],
    );
  }
}

/// Individual language tile widget
class LanguageTile extends StatelessWidget {
  final SupportedLocale locale;
  final bool isSelected;
  final VoidCallback onTap;

  const LanguageTile({
    super.key,
    required this.locale,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Flag emoji or language icon
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Text(
                locale.flagEmoji,
                style: const TextStyle(fontSize: 24.0),
              ),
            ),
            // Language name
            Expanded(
              child: Text(
                locale.displayName,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : null,
                    ),
              ),
            ),
            // Selection indicator
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Icon(
                  Icons.check_circle,
                  color: Theme.of(context).primaryColor,
                  size: 24.0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact language selector dropdown
class LanguageDropdown extends ConsumerWidget {
  final void Function(SupportedLocale)? onChanged;

  const LanguageDropdown({
    super.key,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(currentSupportedLocaleProvider);
    final localizationNotifier = ref.read(localizationProvider.notifier);

    return DropdownButton<SupportedLocale>(
      value: currentLocale,
      items: SupportedLocale.values.map((locale) {
        return DropdownMenuItem(
          value: locale,
          child: Row(
            children: [
              Text(
                locale.flagEmoji,
                style: const TextStyle(fontSize: 20.0),
              ),
              const SizedBox(width: 8.0),
              Text(locale.displayName),
            ],
          ),
        );
      }).toList(),
      onChanged: (selectedLocale) {
        if (selectedLocale != null) {
          localizationNotifier.setLocaleFromEnum(selectedLocale);
          onChanged?.call(selectedLocale);
        }
      },
    );
  }
}
