import 'package:flutter/material.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/registration_screen.dart';
import '../features/individual/screens/my_requirement_screen.dart';
import '../features/individual/screens/post_requirement_screen.dart';

/// Individual-only for this phase — Organisation registration/screens are a
/// later phase (the account-type selector on RegistrationScreen stubs that
/// branch out). No verification-status routing like caregiver-app has: an
/// individual account is either logged in (-> /home) or it isn't (-> /login).
Map<String, WidgetBuilder> buildRoutes() {
  return {
    '/': (context) => const SplashScreen(),
    '/login': (context) => const LoginScreen(),
    '/register': (context) => const RegistrationScreen(),
    '/home': (context) => const MyRequirementScreen(),
    '/post-requirement': (context) => const PostRequirementScreen(),
  };
}
