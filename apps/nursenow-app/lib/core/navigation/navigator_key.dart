import 'package:flutter/material.dart';

/// App-wide navigator key — lets code outside the widget tree (the global
/// session watcher in app.dart, reacting to a token being invalidated by
/// an API call from any screen, not just at splash) redirect to /login
/// without needing a BuildContext of its own.
final navigatorKey = GlobalKey<NavigatorState>();
