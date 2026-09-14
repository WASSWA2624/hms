import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appPopupRouteTrackerProvider = Provider<AppPopupRouteTracker>((ref) {
  final AppPopupRouteTracker tracker = AppPopupRouteTracker();
  ref.onDispose(tracker.dispose);
  return tracker;
});

/// Tracks popup routes (dialogs, bottom sheets, popup menus) open on the app's
/// navigators.
///
/// Controls that float above the router, such as the feedback button, read
/// [hasOpenPopup] to step aside while a popup owns the screen. Attach a fresh
/// [createObserver] to each navigator: the root `GoRouter` and every
/// `ShellRoute`.
final class AppPopupRouteTracker {
  final ValueNotifier<bool> _hasOpenPopup = ValueNotifier<bool>(false);
  final List<_PopupRouteObserver> _observers = <_PopupRouteObserver>[];
  bool _isDisposed = false;

  /// True while any tracked navigator shows a popup route.
  ValueListenable<bool> get hasOpenPopup => _hasOpenPopup;

  /// A new observer for one navigator. A navigator observer cannot be shared.
  NavigatorObserver createObserver() {
    final _PopupRouteObserver observer = _PopupRouteObserver(this);
    _observers.add(observer);
    return observer;
  }

  /// Forgets every observer and open popup.
  ///
  /// Call when the router is rebuilt: its navigators are discarded without
  /// popping their routes, so their observers would otherwise report a popup
  /// forever.
  void reset() {
    for (final _PopupRouteObserver observer in _observers) {
      observer._popups.clear();
    }
    _observers.clear();
    _sync();
  }

  void dispose() {
    _observers.clear();
    _isDisposed = true;
    _hasOpenPopup.dispose();
  }

  void _sync() {
    if (_isDisposed) {
      return;
    }
    _hasOpenPopup.value = _observers.any(
      (_PopupRouteObserver observer) => observer._popups.isNotEmpty,
    );
  }
}

final class _PopupRouteObserver extends NavigatorObserver {
  _PopupRouteObserver(this._tracker);

  final AppPopupRouteTracker _tracker;
  final Set<Route<dynamic>> _popups = <Route<dynamic>>{};

  void _track(Route<dynamic>? route) {
    if (route is PopupRoute<dynamic> && _popups.add(route)) {
      _tracker._sync();
    }
  }

  void _untrack(Route<dynamic>? route) {
    if (route != null && _popups.remove(route)) {
      _tracker._sync();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _untrack(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _untrack(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _untrack(oldRoute);
    _track(newRoute);
  }
}
