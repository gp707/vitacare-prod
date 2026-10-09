import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

// Same backend as core/network/api_client.dart (SPEC.md section 6.1) —
// duplicated rather than importing that file's authenticated Dio/session
// wiring, since this widget sits above the whole app (including before
// login) and must never depend on a session existing.
const String _productionBaseUrl = 'https://api.vitacasahealth.in/v1';
const String _developmentBaseUrl = 'http://localhost:3000/v1';

/// Real reachability probe — a cheap request against our own API's public
/// Rate Card endpoint (the same one every registration/Jobs screen already
/// fetches). `validateStatus: (_) => true` means any HTTP response at all,
/// even an error status, counts as "reachable" — we only care whether the
/// network path to our backend works, not what it says back. Only a
/// genuine connection/DNS/timeout failure (a thrown DioException/
/// SocketException) counts as unreachable.
Future<bool> _defaultReachabilityProbe() async {
  final dio = Dio(
    BaseOptions(
      baseUrl: kReleaseMode ? _productionBaseUrl : _developmentBaseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      validateStatus: (_) => true,
    ),
  );
  try {
    await dio.get('/rate-card');
    return true;
  } catch (_) {
    return false;
  } finally {
    dio.close();
  }
}

/// Wraps the whole app (via MaterialApp.builder, see app.dart) so a
/// "You're offline" banner sits pinned above every screen — Splash, Login,
/// Registration, Jobs Posted, Profile, all of it — the moment connectivity
/// drops, and disappears once it's genuinely back. Purely informational:
/// per CLAUDE.md, mutations already require internet and nothing is queued
/// offline; this just tells the account why an action might be failing —
/// surfaced up front, before they reach a confusing dead end (an empty
/// Salary suggestion, a Terms link that won't open, a submit button that
/// silently does nothing).
///
/// connectivity_plus alone only reports whether a network *interface* is
/// up (Wi-Fi/cellular/none) — a device can report "Wi-Fi connected" while
/// DNS/the internet is actually completely broken (the scenario that
/// prompted this: an emulator whose Wi-Fi adapter was up but could resolve
/// no hostname at all, including google.com). So on top of the existing
/// interface-level listener (instant, for the obvious "no network at all"
/// case), this also runs [_defaultReachabilityProbe] on a short timer, and
/// shows the banner if either check fails. The interface listener can only
/// ever turn the banner ON early; clearing it always goes through a fresh
/// reachability probe, never just "Wi-Fi reconnected," since the interface
/// coming back up doesn't mean DNS/the backend is actually reachable yet.
class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  /// Injectable seams for widget tests — all default to the real
  /// connectivity_plus plugin / a real network probe, never touched in
  /// production code.
  final Future<List<ConnectivityResult>> Function()? initialConnectivity;
  final Stream<List<ConnectivityResult>>? connectivityStream;
  final Future<bool> Function()? checkReachable;
  final Duration probeInterval;

  const ConnectivityBanner({
    super.key,
    required this.child,
    this.initialConnectivity,
    this.connectivityStream,
    this.checkReachable,
    this.probeInterval = const Duration(seconds: 15),
  });

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  bool _offline = false;
  bool _interfaceDown = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _probeTimer;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConnectivity ?? Connectivity().checkConnectivity;
    final stream = widget.connectivityStream ?? Connectivity().onConnectivityChanged;
    initial().then(_onInterfaceResult);
    _subscription = stream.listen(_onInterfaceResult);
    _probeReachability();
    _probeTimer = Timer.periodic(widget.probeInterval, (_) => _probeReachability());
  }

  void _onInterfaceResult(List<ConnectivityResult> results) {
    if (!mounted) return;
    final interfaceDown = results.every((r) => r == ConnectivityResult.none);
    setState(() {
      _interfaceDown = interfaceDown;
      if (interfaceDown) _offline = true;
    });
    // The interface just came back — re-probe immediately rather than
    // waiting for the next periodic tick, so a real reconnection clears
    // the banner promptly.
    if (!interfaceDown) _probeReachability();
  }

  Future<void> _probeReachability() async {
    final check = widget.checkReachable ?? _defaultReachabilityProbe;
    final reachable = await check();
    if (!mounted) return;
    setState(() => _offline = _interfaceDown || !reachable);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _probeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_offline) const VitaOfflineBanner(),
        Expanded(child: widget.child),
      ],
    );
  }
}
