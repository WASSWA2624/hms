import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/app.dart';
import 'package:hosspi_hms/app/router/url_strategy.dart';
import 'package:hosspi_hms/app/startup/app_startup_initializer.dart';
import 'package:hosspi_hms/app/startup/startup_shell.dart';
import 'package:hosspi_hms/core/config/app_config.dart';
import 'package:hosspi_hms/core/logging/app_logger.dart';
import 'package:hosspi_hms/core/utils/client_timezone.dart';
import 'package:hosspi_hms/shared/workflow_actions/workflow_action_dialog_openers.dart';
import 'package:hosspi_hms/shared/workflow_actions/workflow_action_registry.dart';

Future<void> bootstrap({
  AppConfig? config,
  AppStartupInitializer startupInitializer = const AppStartupInitializer(),
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Native platforms report their IANA zone asynchronously; ask early so
  // requests and feedback carry it.
  unawaited(loadClientTimeZoneId());
  configureAppUrlStrategy();
  initializeWorkflowActionRegistry();
  registerWorkflowDialogOpeners();
  final String initialLocation = _platformInitialLocation();

  // Single runApp only: a prior MaterialApp (startup splash) then
  // MaterialApp.router desyncs Flutter web's browser URL from GoRouter.
  try {
    final startupResult = await startupInitializer.initialize(config: config);

    runApp(
      ProviderScope(
        key: UniqueKey(),
        overrides: startupResult
            .providerOverrides(initialLocation: initialLocation)
            .cast(),
        child: const HosspiHmsApp(),
      ),
    );
  } catch (error, stackTrace) {
    AppLogger.error('Startup failed.', error, stackTrace);

    runApp(
      ProviderScope(
        key: UniqueKey(),
        child: StartupErrorApp(
          onRetry: () {
            unawaited(
              bootstrap(config: config, startupInitializer: startupInitializer),
            );
          },
        ),
      ),
    );
  }
}

String _platformInitialLocation() {
  final String routeName =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;

  if (routeName.isEmpty || !routeName.startsWith('/')) {
    return '/';
  }

  return routeName;
}
