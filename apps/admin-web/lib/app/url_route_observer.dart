import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mirrors the current named route into the browser's address bar.
///
/// MaterialApp's classic Navigator doesn't update the URL on its own here, so
/// every sidebar tab and detail page used to leave the address bar stuck on
/// the page the app first loaded at. Reporting the top route's name on every
/// push/pop/replace is what gives each page its own bookmarkable URL (e.g.
/// `#/jobs`, `#/caregivers/<id>`). Unnamed routes (plain MaterialPageRoutes
/// pushed without a name) are ignored, leaving the URL at the last named one.
class UrlRouteObserver extends NavigatorObserver {
  String? _lastReported;

  void _report(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name == '/' || name == _lastReported) return;
    _lastReported = name;
    SystemNavigator.routeInformationUpdated(uri: Uri.parse(name), replace: true);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _report(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(previousRoute);
}
