import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../caregiver/features/auth/state/session_notifier.dart'
    as caregiver_session;
import '../caregiver/features/auth/state/session_state.dart' as caregiver_state;
import '../patient_hospital/core/navigation/navigator_key.dart';

/// Screens a push may open. The payload comes from our own server, but the
/// app still only follows routes it knows — never an arbitrary string.
const _allowedPushRoutes = {
  '/caregiver/jobs',
  '/caregiver/my-jobs',
  '/caregiver/profile'
};

/// The route a push asks to open, or null if there is none / it isn't one the
/// app will follow.
String? routeFromPushData(Map<String, dynamic> data) {
  final route = data['route'];
  return route is String && _allowedPushRoutes.contains(route) ? route : null;
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
/// Only the caregiver flow has push targets today, so a route is followed only
/// when a caregiver session is signed in; for anyone else the tap just opens
/// the app, as before.
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
    final session = ProviderScope.containerOf(context, listen: false)
        .read(caregiver_session.sessionProvider);
    if (session is! caregiver_state.SessionAuthenticated) return;
    _clear();
    navigator.pushNamed(route);
  }

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
