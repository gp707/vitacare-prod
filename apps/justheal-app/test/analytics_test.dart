import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursenow_app/analytics/analytics.dart';
import 'package:nursenow_app/patient_hospital/app/app.dart' show analyticsFlowForRoute;

class _Sink {
  final List<List<Map<String, dynamic>>> batches = [];
  bool failing = false;

  Future<void> call(List<Map<String, dynamic>> events) async {
    if (failing) throw Exception('offline');
    batches.add(events);
  }

  List<Map<String, dynamic>> get all => [for (final b in batches) ...b];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Sink host;
  late _Sink caregiver;

  setUp(() {
    host = _Sink();
    caregiver = _Sink();
    Analytics.init(hostSender: host.call, caregiverSender: caregiver.call);
  });

  tearDown(Analytics.resetForTests);

  test('is a harmless no-op before init (as in every widget test)', () async {
    Analytics.resetForTests();
    Analytics.tap('auth', 'login', 'log_in');
    Analytics.tapHere('rate_card');
    Analytics.screen('auth', '/login');
    await Analytics.flush();
    expect(host.batches, isEmpty);
  });

  test('buffers taps and sends them as one batch on flush, with fixed identifiers only', () async {
    Analytics.tap('auth', 'login', 'log_in');
    Analytics.tap('individual', 'requirement_posted', 'cancel_requirement');
    expect(host.batches, isEmpty, reason: 'nothing is sent per tap');

    await Analytics.flush();

    expect(host.batches, hasLength(1));
    final events = host.batches.single;
    expect(events, hasLength(2));
    expect(events[0], containsPair('kind', 'tap'));
    expect(events[0], containsPair('flow', 'auth'));
    expect(events[0], containsPair('screen', 'login'));
    expect(events[0], containsPair('action', 'log_in'));
    expect(DateTime.tryParse(events[0]['occurred_at'] as String), isNotNull);
    expect(events[0].keys.toSet(), {'kind', 'flow', 'screen', 'action', 'occurred_at'});
  });

  test('a screen view carries no action', () async {
    Analytics.screen('organisation', '/org-home');
    await Analytics.flush();
    final event = host.all.single;
    expect(event['kind'], 'screen');
    expect(event.containsKey('action'), isFalse);
  });

  test('caregiver-flow events go through the caregiver channel, everything else through the host', () async {
    Analytics.tap('caregiver', 'jobs', 'apply');
    Analytics.tap('organisation', 'requirements_posted', 'post_requirement');
    await Analytics.flush();
    expect(caregiver.all.map((e) => e['action']), ['apply']);
    expect(host.all.map((e) => e['action']), ['post_requirement']);
  });

  test('sends a full batch immediately and never exceeds the backend per-request cap', () async {
    for (var i = 0; i < Analytics.maxBatch; i++) {
      Analytics.tap('auth', 'login', 'log_in');
    }
    await Future<void>.delayed(Duration.zero);
    expect(host.batches, hasLength(1));
    expect(host.batches.single, hasLength(Analytics.maxBatch));

    for (var i = 0; i < 60; i++) {
      Analytics.tap('auth', 'login', 'log_in');
    }
    await Analytics.flush();
    expect(host.batches.every((b) => b.length <= Analytics.maxBatch), isTrue);
    expect(host.all, hasLength(Analytics.maxBatch + 60));
  });

  test('keeps events when the send fails and delivers them on a later flush', () async {
    host.failing = true;
    Analytics.tap('auth', 'login', 'log_in');
    await Analytics.flush(); // must not throw
    expect(host.batches, isEmpty);

    host.failing = false;
    await Analytics.flush();
    expect(host.all.map((e) => e['action']), ['log_in']);
  });

  test('is bounded while offline: the oldest events are dropped, never unbounded growth', () async {
    host.failing = true;
    for (var i = 0; i < Analytics.maxBuffered + 50; i++) {
      Analytics.tap('auth', 'login', 'tap_$i');
    }
    await Analytics.flush();
    host.failing = false;
    await Analytics.flush();

    expect(host.all, hasLength(Analytics.maxBuffered));
    expect(host.all.first['action'], 'tap_50', reason: 'the 50 oldest were dropped');
    expect(host.all.last['action'], 'tap_${Analytics.maxBuffered + 49}');
  });

  test('tapHere attributes a shared-widget tap to the current location set by the navigator observer', () async {
    final observer = AnalyticsNavigatorObserver(flowFor: (name) => analyticsFlowForRoute(name, role: 'organisation'));
    observer.didPush(MaterialPageRoute<void>(settings: const RouteSettings(name: '/profile'), builder: (_) => const SizedBox()), null);

    Analytics.tapHere('rate_card');
    await Analytics.flush();

    final events = host.all;
    expect(events.first, containsPair('kind', 'screen'));
    expect(events.first, containsPair('flow', 'organisation'));
    expect(events.first, containsPair('screen', '/profile'));
    expect(events.last, containsPair('action', 'rate_card'));
    expect(events.last, containsPair('flow', 'organisation'));
    expect(events.last, containsPair('screen', '/profile'));
  });

  test('the observer ignores unnamed routes, and reports an earlier page again when the user navigates back to it', () async {
    final observer = AnalyticsNavigatorObserver(flowFor: (name) => analyticsFlowForRoute(name));
    Route<void> named(String name) =>
        MaterialPageRoute<void>(settings: RouteSettings(name: name), builder: (_) => const SizedBox());

    observer.didPush(named('/login'), null);
    observer.didPush(MaterialPageRoute<void>(builder: (_) => const SizedBox()), named('/login')); // unnamed: ignored
    observer.didPush(named('/register'), named('/login'));
    observer.didPop(named('/register'), named('/login')); // back to /login
    await Analytics.flush();

    expect(host.all.map((e) => e['screen']), ['/login', '/register', '/login']);
  });

  test('opening/closing a dialog or dropdown is not a screen view; popping a real page back is', () async {
    final observer = AnalyticsNavigatorObserver(flowFor: (name) => analyticsFlowForRoute(name));
    Route<void> page(String name) =>
        MaterialPageRoute<void>(settings: RouteSettings(name: name), builder: (_) => const SizedBox());

    observer.didPush(page('/register'), page('/login'));
    final dialog = RawDialogRoute<void>(pageBuilder: (_, __, ___) => const SizedBox());
    observer.didPush(dialog, page('/register'));
    observer.didPop(dialog, page('/register')); // closing the dialog must NOT re-report /register
    await Analytics.flush();
    expect(host.all.map((e) => e['screen']), ['/register']);

    // A genuine back navigation to an earlier, different page is a view of it.
    observer.didPop(page('/register'), page('/login'));
    await Analytics.flush();
    expect(host.all.map((e) => e['screen']), ['/register', '/login']);
  });

  test('the same screen reached twice in quick succession is one view (e.g. two redirects to /login)', () async {
    final observer = AnalyticsNavigatorObserver(flowFor: (name) => analyticsFlowForRoute(name));
    Route<void> page(String name) =>
        MaterialPageRoute<void>(settings: RouteSettings(name: name), builder: (_) => const SizedBox());

    observer.didPush(page('/login'), null);
    observer.didPush(page('/login'), null);
    observer.didReplace(newRoute: page('/login'), oldRoute: page('/'));
    observer.didPush(page('/register'), page('/login'));
    await Analytics.flush();

    expect(host.all.map((e) => e['screen']), ['/login', '/register']);
  });

  group('analyticsFlowForRoute', () {
    test('namespaces caregiver routes and auth routes', () {
      expect(analyticsFlowForRoute('/caregiver/jobs'), 'caregiver');
      expect(analyticsFlowForRoute('/caregiver/login', role: 'individual'), 'caregiver');
      for (final route in ['/', '/login', '/register']) {
        expect(analyticsFlowForRoute(route, role: 'individual'), 'auth');
      }
    });

    test('org-only routes are organisation regardless of role; shared routes follow the logged-in role', () {
      expect(analyticsFlowForRoute('/org-home'), 'organisation');
      expect(analyticsFlowForRoute('/profile', role: 'organisation'), 'organisation');
      expect(analyticsFlowForRoute('/profile', role: 'individual'), 'individual');
      expect(analyticsFlowForRoute('/home', role: 'individual'), 'individual');
      expect(analyticsFlowForRoute('/profile'), 'auth');
    });
  });
}
