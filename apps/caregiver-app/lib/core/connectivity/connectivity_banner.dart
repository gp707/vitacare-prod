import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Wraps the whole app (via MaterialApp.builder, see app.dart) so a
/// "You're offline" banner sits pinned above every screen — Splash, Login,
/// Jobs, Profile, all of it — the moment connectivity drops, and
/// disappears the moment it's back. Purely informational: per CLAUDE.md,
/// mutations already require internet and nothing is queued offline; this
/// just tells the caregiver why an action might be failing.
class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_onResults);
    _subscription = Connectivity().onConnectivityChanged.listen(_onResults);
  }

  void _onResults(List<ConnectivityResult> results) {
    if (!mounted) return;
    setState(() => _offline = results.every((r) => r == ConnectivityResult.none));
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
