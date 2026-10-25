import 'package:flutter/material.dart';

/// App-level hook for a single tap on the brand logo. vitacare_ui stays free
/// of anything app-specific (version lookup, URLs, dialogs), so the host app
/// registers what a logo tap does once at startup and every logo — the
/// AppBar icon on each screen, the login-screen logos — picks it up without
/// each call site having to pass anything. Left null (admin-web, tests) the
/// logos are inert, exactly as before.
class VitaBrandActions {
  VitaBrandActions._();

  static void Function(BuildContext context)? onLogoTap;
}

/// Makes a static logo respond to [VitaBrandActions.onLogoTap].
class VitaLogoTap extends StatelessWidget {
  final Widget child;

  const VitaLogoTap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('vitaLogoTap'),
      behavior: HitTestBehavior.opaque,
      onTap: () => VitaBrandActions.onLogoTap?.call(context),
      child: child,
    );
  }
}
