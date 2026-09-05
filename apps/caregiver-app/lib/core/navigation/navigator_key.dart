import 'package:flutter/material.dart';

/// Lets code outside the widget tree (the auth interceptor's onError
/// callback) navigate to /login the moment a request comes back with an
/// invalid/expired token, without needing a BuildContext of its own.
final navigatorKey = GlobalKey<NavigatorState>();
