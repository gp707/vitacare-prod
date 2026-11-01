import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../caregiver/features/auth/state/session_notifier.dart'
    as caregiver_session;
import '../caregiver/features/auth/state/session_state.dart' as caregiver_state;
import '../patient_hospital/core/navigation/navigator_key.dart';
import '../patient_hospital/features/auth/state/session_notifier.dart'
    as host_session;
import '../patient_hospital/features/auth/state/session_state.dart'
    as host_state;

/// Screens a push may open, and who may be taken there. The payload comes from
/// our own server, but the app still only follows routes it knows — never an
/// arbitrary string — and only for the signed-in role the screen belongs to:
/// a caregiver's "you were accepted" must never open a patient screen, or any
/// screen at all for someone signed in as a different kind of account.
enum _PushAudience { caregiver, individual, organisation }

const _pushRoutes = <String, _PushAudience>{
  '/caregiver/jobs': _PushAudience.caregiver,
  '/caregiver/my-jobs': _PushAudience.caregiver,
  '/caregiver/profile': _PushAudience.caregiver,
  '/home': _PushAudience.individual,
  '/org-home': _PushAudience.organisation,
};

/// The route a push asks to open, or null if there is none / it isn't one the
/// app will follow.
String? routeFromPushData(Map<String, dynamic> data) {
  final route = data['route'];
  return route is String && _pushRoutes.containsKey(route) ? route : null;
}

/// How long a tapped push waits for the session to finish loading before it
/// is dropped — a stale tap must not yank someone to a screen minutes later.
const pendingPushRouteLifetime = Duration(minutes: 2);

/// Tap-through and in-app display for FCM pushes.
///
/// - Tapped while the app was in the background -> open the target screen.
/// - Tapped while the app was closed -> remembered until the splash screen has
///   restored the session, then opened ([deliverPending]).
/// - Received while the app is open -> Android shows nothing on its own, so an
///   in-app banner is shown with a "View" shortcut.
///
/// A route is followed only when the matching kind of account is signed in
/// (caregiver, patient/family, or organisation); for anyone else the tap just
/// opens the app, as before.
class PushHandler {
  PushHandler._();
  static final instance = PushHandler._();

  String? _pendingRoute;
  DateTime? _pendingSince;
  bool _started = false;

  /// Safe to call when Firebase isn't configured (web/dev, tests): it
  /// swallows the failure and push simply isn't wired up.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _remember(m));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _remember(initial, deliverNow: false);
    } catch (_) {
      // Best-effort, same as FcmService.
    }
  }

  void _remember(RemoteMessage message, {bool deliverNow = true}) {
    final route = routeFromPushData(message.data);
    if (route == null) return;
    _pendingRoute = route;
    _pendingSince = DateTime.now();
    if (deliverNow) deliverPending();
  }

  /// Opens the remembered route if a caregiver session is ready. Called on a
  /// warm tap, and by the splash screen once it has restored the session.
  void deliverPending() {
    final route = _pendingRoute;
    final since = _pendingSince;
    if (route == null || since == null) return;
    if (DateTime.now().difference(since) > pendingPushRouteLifetime) {
      _clear();
      return;
    }
    final context = navigatorKey.currentContext;
    final navigator = navigatorKey.currentState;
    if (context == null || navigator == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final audience = _pushRoutes[route]!;
    if (audience == _PushAudience.caregiver) {
      if (container.read(caregiver_session.sessionProvider)
          is! caregiver_state.SessionAuthenticated) {
        return;
      }
      _clear();
      // On top of wherever they are, so Back returns them to it.
      navigator.pushNamed(route);
      return;
    }
    final session = container.read(host_session.sessionProvider);
    if (session is! host_state.SessionAuthenticated) return;
    final signedInAs = session.role == 'organisation'
        ? _PushAudience.organisation
        : _PushAudience.individual;
    if (signedInAs != audience) return;
    _clear();
    // These are the account's home screen, so replace the stack rather than
    // stacking a second copy of the screen they may already be on.
    navigator.pushNamedAndRemoveUntil(route, (_) => false);
  }

  /// Drops a remembered tap. Used when the app has just opened on the account's
  /// own home screen, which is where that tap was going anyway.
  void discardPending() => _clear();

  void _clear() {
    _pendingRoute = null;
    _pendingSince = null;
  }

  void _onForegroundMessage(RemoteMessage message) {
    final context = navigatorKey.currentContext;
    final notification = message.notification;
    if (context == null || notification == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final route = routeFromPushData(message.data);
    final text = [notification.title, notification.body]
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .join('\n');
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 6),
        action: route == null
            ? null
            : SnackBarAction(
                label: 'View',
                onPressed: () {
                  _pendingRoute = route;
                  _pendingSince = DateTime.now();
                  deliverPending();
                },
              ),
      ),
    );
  }
}
