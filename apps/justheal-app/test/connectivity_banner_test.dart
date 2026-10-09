import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'package:nursenow_app/patient_hospital/core/connectivity/connectivity_banner.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<ConnectivityResult>> Function() initialConnectivity,
  required Stream<List<ConnectivityResult>> connectivityStream,
  required Future<bool> Function() checkReachable,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ConnectivityBanner(
        initialConnectivity: initialConnectivity,
        connectivityStream: connectivityStream,
        checkReachable: checkReachable,
        probeInterval: const Duration(seconds: 15),
        child: const Scaffold(body: Text('Registration Form')),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('no banner when the interface is connected and the backend is actually reachable', (tester) async {
    await _pump(
      tester,
      initialConnectivity: () async => [ConnectivityResult.wifi],
      connectivityStream: const Stream.empty(),
      checkReachable: () async => true,
    );

    expect(find.byType(VitaOfflineBanner), findsNothing);
    expect(find.text('Registration Form'), findsOneWidget);
  });

  testWidgets('shows the banner immediately when the interface itself reports no connection', (tester) async {
    await _pump(
      tester,
      initialConnectivity: () async => [ConnectivityResult.none],
      connectivityStream: const Stream.empty(),
      checkReachable: () async => true,
    );

    expect(find.byType(VitaOfflineBanner), findsOneWidget);
  });

  testWidgets(
      'shows the banner when the interface reports connected but the real reachability probe fails — '
      'the exact DNS-broken-emulator scenario interface-only detection misses', (tester) async {
    await _pump(
      tester,
      initialConnectivity: () async => [ConnectivityResult.wifi],
      connectivityStream: const Stream.empty(),
      checkReachable: () async => false,
    );

    expect(find.byType(VitaOfflineBanner), findsOneWidget);
  });

  testWidgets('the banner clears once a later reachability probe succeeds, triggered by the interface reconnecting',
      (tester) async {
    final controller = StreamController<List<ConnectivityResult>>();
    var reachable = false;

    await _pump(
      tester,
      initialConnectivity: () async => [ConnectivityResult.none],
      connectivityStream: controller.stream,
      checkReachable: () async => reachable,
    );
    expect(find.byType(VitaOfflineBanner), findsOneWidget);

    // Interface reconnects, and this time the backend is actually
    // reachable — the banner should clear via the immediate re-probe
    // triggered by the interface coming back up, not wait for the next
    // periodic tick.
    reachable = true;
    controller.add([ConnectivityResult.wifi]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(VitaOfflineBanner), findsNothing);
    await controller.close();
  });

  testWidgets(
      'the interface reconnecting does NOT clear the banner by itself if the backend is still unreachable',
      (tester) async {
    final controller = StreamController<List<ConnectivityResult>>();

    await _pump(
      tester,
      initialConnectivity: () async => [ConnectivityResult.none],
      connectivityStream: controller.stream,
      checkReachable: () async => false,
    );
    expect(find.byType(VitaOfflineBanner), findsOneWidget);

    // Wi-Fi interface reports back up, but the probe still fails (DNS
    // still broken) — must stay offline, not clear just because the
    // adapter itself reconnected.
    controller.add([ConnectivityResult.wifi]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(VitaOfflineBanner), findsOneWidget);
    await controller.close();
  });
}
