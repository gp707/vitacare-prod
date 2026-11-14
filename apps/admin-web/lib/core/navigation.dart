import 'package:flutter/material.dart';

/// Lets code outside the widget tree (the API client, when the server says
/// the session has ended) send the admin back to the login screen.
final adminNavigatorKey = GlobalKey<NavigatorState>();
final adminMessengerKey = GlobalKey<ScaffoldMessengerState>();
