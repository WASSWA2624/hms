import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/security/auth_session.dart';
import 'package:hosspi_hms/core/security/session_tokens.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_screen_catalog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';

AppAccessPolicy _policyFor(List<String> roles) {
  return AppAccessPolicy.fromSession(
    AuthSession(
      tokens: SessionTokens(accessToken: 'test-access-token'),
      user: AuthUserProfile(
        id: 'user-1',
        email: 'user@example.com',
        tenantId: 'tenant-1',
        roles: roles,
      ),
    ),
  );
}

Iterable<String> _routeNames(List<FeedbackScreenChoice> choices) =>
    choices.map((FeedbackScreenChoice choice) => choice.screen.routeName!);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('names every screen the way the navigation names it', () {
    final List<FeedbackScreenChoice> catalog = feedbackScreenCatalog(l10n);

    expect(
      catalog.firstWhere(
        (FeedbackScreenChoice choice) => choice.screen.routeName == 'opd',
      ).label,
      l10n.navigationOpdLabel,
    );
    // Every choice can be addressed by the API.
    for (final FeedbackScreenChoice choice in catalog) {
      expect(choice.screen.isAddressable, isTrue);
      expect(choice.label, isNotEmpty);
    }
  });

  test('a signed-out reporter sees only the public screens', () {
    final List<FeedbackScreenChoice> choices = reachableFeedbackScreens(
      l10n: l10n,
      policy: AppAccessPolicy.fromSession(null),
      signedIn: false,
    );

    expect(_routeNames(choices), containsAll(<String>['login', 'register']));
    expect(_routeNames(choices), isNot(contains('hr')));
    expect(_routeNames(choices), isNot(contains('pharmacy')));
  });

  test('a signed-in reporter sees the workspaces their account can open', () {
    final List<FeedbackScreenChoice> owner = reachableFeedbackScreens(
      l10n: l10n,
      policy: _policyFor(<String>['PLATFORM_OWNER']),
      signedIn: true,
    );
    final List<FeedbackScreenChoice> nurse = reachableFeedbackScreens(
      l10n: l10n,
      policy: _policyFor(<String>['NURSE']),
      signedIn: true,
    );

    expect(_routeNames(owner), contains('accessAdmin'));
    // Nobody files feedback against a workspace they cannot reach.
    expect(_routeNames(nurse), isNot(contains('accessAdmin')));
    expect(nurse.length, lessThan(owner.length));
  });

  test('names the screen a route belongs to, or falls back to the route', () {
    expect(
      feedbackScreenForRoute(l10n: l10n, routeName: 'opd')?.screenTitle,
      l10n.navigationOpdLabel,
    );
    // A screen outside the catalogue still travels with the feedback.
    final FeedbackScreenReference? unknown = feedbackScreenForRoute(
      l10n: l10n,
      routeName: 'someFutureScreen',
      routePath: '/future',
    );
    expect(unknown?.routeName, 'someFutureScreen');
    expect(unknown?.routePath, '/future');
    expect(
      feedbackScreenForRoute(l10n: l10n, routeName: null, routePath: '  '),
      isNull,
    );
  });
}
