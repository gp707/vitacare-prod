import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// Every widget test in this app was written against the desktop/laptop
/// sidebar layout. AppShell now switches to a compact drawer layout below
/// the tablet breakpoint (see vitacare_ui's AppBreakpoints), and Flutter
/// test's own default surface is narrower than that breakpoint — without
/// this, every test that doesn't call its own `tester.binding
/// .setSurfaceSize(...)` would silently start rendering the mobile drawer
/// instead of the sidebar it was written against.
///
/// Sets the underlying test view's `physicalSize`/`devicePixelRatio`
/// directly rather than `TestWidgetsFlutterBinding.setSurfaceSize` —
/// the latter asserts `inTest`, which isn't true yet while `setUp`
/// callbacks run, only once a `testWidgets` body is actually executing.
/// `physicalSize`/`devicePixelRatio` carry no such guard, and a test's own
/// `setSurfaceSize(...)` (which takes priority whenever set) still works
/// exactly as before — this only supplies the fallback once that test's own
/// `setSurfaceSize(null)` teardown clears its override. Runs before every
/// individual test (not just once per file), so it re-applies every time.
/// A test that specifically wants to exercise the compact/mobile layout
/// should call `tester.binding.setSurfaceSize(...)` with its own narrow
/// size, same as any other test overriding this default.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
  });
  await testMain();
}
