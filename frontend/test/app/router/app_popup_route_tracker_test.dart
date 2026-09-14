import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/app/router/app_popup_route_tracker.dart';

void main() {
  Future<GlobalKey<NavigatorState>> pumpNavigator(
    WidgetTester tester,
    AppPopupRouteTracker tracker,
  ) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: <NavigatorObserver>[tracker.createObserver()],
        home: const Scaffold(body: Text('Home')),
      ),
    );
    return navigatorKey;
  }

  testWidgets('reports a popup while a dialog is open', (
    WidgetTester tester,
  ) async {
    final AppPopupRouteTracker tracker = AppPopupRouteTracker();
    addTearDown(tracker.dispose);
    final GlobalKey<NavigatorState> navigatorKey = await pumpNavigator(
      tester,
      tracker,
    );

    expect(tracker.hasOpenPopup.value, isFalse);

    unawaited(
      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Popup')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tracker.hasOpenPopup.value, isTrue);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tracker.hasOpenPopup.value, isFalse);
  });

  testWidgets('ignores page routes', (WidgetTester tester) async {
    final AppPopupRouteTracker tracker = AppPopupRouteTracker();
    addTearDown(tracker.dispose);
    final GlobalKey<NavigatorState> navigatorKey = await pumpNavigator(
      tester,
      tracker,
    );

    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Details')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsOneWidget);
    expect(tracker.hasOpenPopup.value, isFalse);
  });

  testWidgets('reset forgets popups from discarded navigators', (
    WidgetTester tester,
  ) async {
    final AppPopupRouteTracker tracker = AppPopupRouteTracker();
    addTearDown(tracker.dispose);
    final GlobalKey<NavigatorState> navigatorKey = await pumpNavigator(
      tester,
      tracker,
    );

    unawaited(
      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Popup')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tracker.hasOpenPopup.value, isTrue);

    tracker.reset();
    expect(tracker.hasOpenPopup.value, isFalse);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tracker.hasOpenPopup.value, isFalse);
  });
}
