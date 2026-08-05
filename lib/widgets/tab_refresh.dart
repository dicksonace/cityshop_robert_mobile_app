import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/app_store.dart';

/// How often a tab that is on screen re-pulls its data.
const Duration kTabAutoRefresh = Duration(seconds: 20);

/// Publishes the visible bottom-nav slot so hidden tabs stop polling.
class ActiveTab extends InheritedWidget {
  const ActiveTab({super.key, required this.index, required super.child});

  final int index;

  static int? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActiveTab>()?.index;

  @override
  bool updateShouldNotify(ActiveTab oldWidget) => oldWidget.index != index;
}

/// Keeps a bottom-nav tab's data current.
///
/// The shell builds every tab at once, so without this a tab that was created
/// while the session was still being restored (or before the buyer logged in)
/// kept showing an empty state until the app was killed and reopened. Data is
/// (re)loaded on first paint, after login or logout, when the tab is reopened,
/// when the app returns to the foreground, and every [kTabAutoRefresh].
mixin AutoRefreshTab<T extends StatefulWidget> on State<T> {
  /// Bottom-nav slot this tab lives in; null means "always on screen".
  int? get tabIndex => null;

  /// Tabs that have nothing to show until someone is signed in.
  bool get refreshNeedsLogin => true;

  /// Set when the store already holds this tab's data (the splash screen
  /// preloads some of it), so the first paint does not refetch it.
  bool get tabAlreadyHasData => false;

  /// [background] is true for the silent 20s ticks, so implementations can
  /// leave the current content in place instead of flashing a loader.
  Future<void> refreshTabData({required bool background});

  Timer? _ticker;
  AppLifecycleListener? _lifecycle;
  AppStore? _store;
  int? _sessionUserId;
  int? _visibleIndex;
  bool _inTabScope = false;
  bool _loaded = false;
  bool _busy = false;
  bool _foreground = true;
  bool _wasOnScreen = false;

  bool get isTabVisible => tabIndex == null || _visibleIndex == tabIndex;

  /// True while the session is still being restored and nothing has loaded yet,
  /// so a tab can show a loader instead of a misleading "please log in" screen.
  bool get tabIsWarmingUp => !_loaded && (_store?.booting ?? false);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        final foreground = state == AppLifecycleState.resumed;
        if (foreground == _foreground) return;
        _foreground = foreground;
        if (foreground) {
          _sync();
        } else {
          _stopTicker();
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final activeIndex = ActiveTab.maybeOf(context);
    _inTabScope = activeIndex != null;
    _visibleIndex = activeIndex ?? tabIndex;

    final store = context.read<AppStore>();
    if (!identical(store, _store)) {
      _store?.removeListener(_handleStoreChanged);
      _store = store..addListener(_handleStoreChanged);
      _sessionUserId = store.user?.id;
    }

    _sync();
  }

  @override
  void dispose() {
    _stopTicker();
    _lifecycle?.dispose();
    _store?.removeListener(_handleStoreChanged);
    super.dispose();
  }

  /// Pull-to-refresh and Retry buttons both land here.
  Future<void> refreshNow() => _run(background: false);

  void _handleStoreChanged() {
    final userId = _store?.user?.id;
    if (userId != _sessionUserId) {
      _sessionUserId = userId;
      _loaded = false;
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  void _sync() {
    final store = _store;
    if (store == null || !mounted) return;

    final onScreen = isTabVisible && _foreground;
    final reopened = onScreen && !_wasOnScreen;
    _wasOnScreen = onScreen;

    if (!onScreen) {
      _stopTicker();
      return;
    }

    if (refreshNeedsLogin && !store.isLoggedIn) {
      _stopTicker();
      return;
    }

    if (!_loaded) {
      _loaded = true;
      if (!tabAlreadyHasData) {
        _runAfterFrame(background: false);
      }
    } else if (reopened) {
      // Coming back to a tab (or to the app) shows current data right away
      // instead of whatever was on screen when it was last left.
      _runAfterFrame(background: true);
    }

    // Only tabs living in the shell's [ActiveTab] scope poll; a tab pumped on
    // its own (widget tests, one-off screens) just loads once.
    if (_inTabScope) {
      _ticker ??= Timer.periodic(kTabAutoRefresh, (_) => _run(background: true));
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _runAfterFrame({required bool background}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run(background: background));
    });
  }

  Future<void> _run({required bool background}) async {
    if (_busy || !mounted) return;
    if (background && (!isTabVisible || !_foreground)) return;

    _busy = true;
    try {
      await refreshTabData(background: background);
    } catch (_) {
      // Tabs surface their own errors; a failed tick must not stop the timer.
    } finally {
      _busy = false;
    }
  }
}
