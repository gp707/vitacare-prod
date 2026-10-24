import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

/// Sends one batch of events. Throwing is fine — the tracker swallows it.
typedef EventSender = Future<void> Function(List<Map<String, dynamic>> events);

/// Usage telemetry for the admin "Insights" screen: which screens people
/// open and which buttons they press, reported to `POST /events`.
///
/// Design constraints, all because this must never hurt the app it observes:
///  * **Fire-and-forget.** `tap()`/`screen()` return immediately; nothing
///    awaits the network. Failures are swallowed.
///  * **Batched.** Events are buffered and sent every [flushInterval], when a
///    batch fills, and when the app goes to the background — not one request
///    per tap.
///  * **Bounded.** At most [maxBuffered] events are held per channel; if the
///    device is offline for long, the oldest are dropped rather than growing
///    without limit.
///  * **Inert until initialised.** Before [init] (and in every widget test)
///    all calls are no-ops, so instrumented screens need no setup to test.
///  * **No content.** Only fixed identifiers (flow/screen/action) are sent —
///    never anything a user typed.
///
/// There are two channels because the merged JustHeal binary has two
/// independent sessions (the host's individual/organisation session and the
/// caregiver flow's own session, each with its own token and API client): an
/// event is sent through the channel whose session it belongs to, so it is
/// attributed to the right account.
class Analytics with WidgetsBindingObserver {
  Analytics._();

  static final Analytics _instance = Analytics._();

  /// The flow name used for the caregiver (NurseJobs) part of the app; every
  /// other flow is sent through the host session.
  static const caregiverFlow = 'caregiver';

  static const flushInterval = Duration(seconds: 15);
  static const maxBatch = 25; // matches the backend's per-request cap
  static const maxBuffered = 200;

  _Channel? _host;
  _Channel? _caregiver;
  Timer? _timer;
  bool _observing = false;

  /// Current location, maintained by [AnalyticsNavigatorObserver] — lets
  /// shared widgets (Rate Card, Help, text size, messages bell…) report a
  /// tap without knowing which screen or flow they were placed on.
  String _currentFlow = 'auth';
  String _currentScreen = '/';

  /// Wires the two senders. Safe to call again (e.g. a hot restart or a test
  /// that re-initialises): the previous state is replaced.
  static void init({required EventSender hostSender, required EventSender caregiverSender}) {
    _instance._init(hostSender, caregiverSender);
  }

  /// Convenience for production wiring: sends through each flow's own Dio
  /// (whose interceptor attaches that flow's token).
  static void initWithDio({required Dio hostDio, required Dio caregiverDio}) {
    init(
      hostSender: (events) => hostDio.post('/events', data: {'events': events}),
      caregiverSender: (events) => caregiverDio.post('/events', data: {'events': events}),
    );
  }

  /// Records a button press. [flow] is 'auth'/'individual'/'organisation'/
  /// 'caregiver'; [screen] a short stable screen id; [action] the button.
  static void tap(String flow, String screen, String action) =>
      _instance._record(kind: 'tap', flow: flow, screen: screen, action: action);

  /// A tap from a widget shared across screens — attributed to wherever the
  /// user currently is.
  static void tapHere(String action) =>
      _instance._record(kind: 'tap', flow: _instance._currentFlow, screen: _instance._currentScreen, action: action);

  /// Records a screen view.
  static void screen(String flow, String screen) => _instance._record(kind: 'screen', flow: flow, screen: screen);

  /// Called by the navigator observer so [tapHere] knows where the user is.
  static void setLocation(String flow, String screen) {
    _instance._currentFlow = flow;
    _instance._currentScreen = screen;
  }

  /// Sends anything buffered now (used on app pause; tests await it).
  static Future<void> flush() => _instance._flushAll();

  /// Drops all state and stops timers — for tests.
  static void resetForTests() => _instance._reset();

  // ---------------------------------------------------------------------

  void _init(EventSender hostSender, EventSender caregiverSender) {
    _reset();
    _host = _Channel(hostSender);
    _caregiver = _Channel(caregiverSender);
    _timer = Timer.periodic(flushInterval, (_) => _flushAll());
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    _host = null;
    _caregiver = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _currentFlow = 'auth';
    _currentScreen = '/';
  }

  void _record({required String kind, required String flow, required String screen, String? action}) {
    final channel = flow == caregiverFlow ? _caregiver : _host;
    if (channel == null) return; // not initialised
    channel.add({
      'kind': kind,
      'flow': flow,
      'screen': screen,
      if (action != null) 'action': action,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (channel.buffer.length >= maxBatch) unawaited(channel.flush());
  }

  Future<void> _flushAll() async {
    await Future.wait([
      if (_host != null) _host!.flush(),
      if (_caregiver != null) _caregiver!.flush(),
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(_flushAll());
    }
  }
}

class _Channel {
  final EventSender _send;
  final List<Map<String, dynamic>> buffer = [];
  Future<void>? _running;

  _Channel(this._send);

  void add(Map<String, dynamic> event) {
    buffer.add(event);
    if (buffer.length > Analytics.maxBuffered) {
      buffer.removeRange(0, buffer.length - Analytics.maxBuffered);
    }
  }

  /// Completes once everything buffered at call time (and anything added
  /// while it runs) has been sent, or the first send fails. A second caller
  /// while a send is in flight waits for that same drain instead of
  /// returning early — so awaiting this on app pause really means "sent".
  Future<void> flush() async {
    final running = _running;
    if (running != null) {
      await running;
      return;
    }
    if (buffer.isEmpty) return;
    final drain = _drain();
    _running = drain;
    try {
      await drain;
    } finally {
      _running = null;
    }
  }

  Future<void> _drain() async {
    while (buffer.isNotEmpty) {
      final batch = buffer.take(Analytics.maxBatch).toList();
      try {
        await _send(batch);
      } catch (_) {
        // Offline/server error: keep the events for the next flush
        // (bounded by maxBuffered) and stop for now.
        return;
      }
      buffer.removeRange(0, batch.length);
    }
  }
}

/// Reports a screen view each time a *named* route becomes visible, and tells
/// [Analytics] where the user currently is (for shared-widget taps).
///
/// [flowFor] maps a route name to a flow; it is supplied by the app because
/// the host's shared routes (e.g. `/profile`) belong to either the individual
/// or the organisation flow depending on the logged-in role.
class AnalyticsNavigatorObserver extends NavigatorObserver {
  final String Function(String routeName) flowFor;

  /// The app can navigate to the same screen twice in quick succession (e.g.
  /// the splash screen and the session watcher both sending an
  /// unauthenticated user to /login) — that is one view, not two.
  static const dedupeWindow = Duration(seconds: 2);

  String? _lastName;
  DateTime? _lastAt;

  AnalyticsNavigatorObserver({required this.flowFor});

  void _visit(Route<dynamic>? route) {
    // Only real pages count as screens. Dropdown menus, dialogs and bottom
    // sheets are PopupRoutes: opening one is not a screen view, and — more
    // importantly — *closing* one pops back to the page underneath, which
    // would otherwise be reported as that page being viewed again.
    if (route is! PageRoute) return;
    final name = route.settings.name;
    // Unnamed MaterialPageRoutes (a screen pushed from inside another) can't
    // be identified, so they are not reported as screens; taps made on them
    // are still reported explicitly by the buttons themselves.
    if (name == null || name.isEmpty) return;

    final now = DateTime.now();
    if (name == _lastName && _lastAt != null && now.difference(_lastAt!) < dedupeWindow) return;
    _lastName = name;
    _lastAt = now;

    final flow = flowFor(name);
    Analytics.setLocation(flow, name);
    Analytics.screen(flow, name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _visit(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _visit(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Popping a popup/dialog reveals the page underneath, which was already
    // counted when it was opened — only a popped *page* is a real navigation
    // back to the previous page.
    if (route is PageRoute) _visit(previousRoute);
  }
}
