import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android Back on a bottom-nav tab steps back through the tabs instead of
/// closing the app: MyJobs -> Jobs -> Profile, and Back on Profile closes it.
/// Screens pushed on top (dialogs, edit screens) pop normally first — this
/// only handles Back while the tab itself is the top route.
class TabBackScope extends StatelessWidget {
  final Widget child;

  /// Route to go to on Back; null on the first tab, where Back closes the app.
  final String? backRoute;

  /// Handles Back inside the screen first (e.g. the previous sub-tab).
  /// Returns true if it consumed the press.
  final bool Function()? onBackFirst;

  const TabBackScope(
      {super.key, required this.child, this.backRoute, this.onBackFirst});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (onBackFirst?.call() ?? false) return;
        if (backRoute != null) {
          Navigator.of(context).pushReplacementNamed(backRoute!);
        } else {
          SystemNavigator.pop();
        }
      },
      child: child,
    );
  }
}
