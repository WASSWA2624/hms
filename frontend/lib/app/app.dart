import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/accessibility/app_accessibility_controller.dart';
import 'package:hosspi_hms/app/accessibility/app_accessibility_preferences.dart';
import 'package:hosspi_hms/app/locale/app_locale_controller.dart';
import 'package:hosspi_hms/app/router/app_router.dart';
import 'package:hosspi_hms/app/startup/session_bootstrap.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/app/theme/app_theme_mode_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/app_feedback_host.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';

class HosspiHmsApp extends ConsumerWidget {
  const HosspiHmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final locale = ref.watch(appLocaleProvider);
    final GoRouter router = ref.watch(appRouterProvider);

    return SessionBootstrap(
      child: MaterialApp.router(
        onGenerateTitle: (BuildContext context) => context.l10n.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
        builder: (BuildContext context, Widget? child) {
          if (child == null) {
            return const SizedBox.shrink();
          }
          return _AccessibilityMediaQueryWrapper(
            // Above the navigators, so every screen — sign-in included — and
            // any screen added later gets the feedback control.
            child: AppFeedbackHost(router: router, child: child),
          );
        },
      ),
    );
  }
}

class _AccessibilityMediaQueryWrapper extends ConsumerWidget {
  const _AccessibilityMediaQueryWrapper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppAccessibilityPreferences accessibility = ref.watch(
      appAccessibilityProvider,
    );
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        disableAnimations: accessibility.reduceMotion,
        boldText: accessibility.boldText,
        textScaler: TextScaler.linear(accessibility.textScaleFactor),
      ),
      child: child,
    );
  }
}
