import 'package:flutter/material.dart';

/// SPEC.md 12: "Show bottom navigation bar at all times after registration
/// (including pending statuses). Seeing jobs motivates caregivers to
/// complete onboarding." Each screen owns its own Scaffold/AppBar and just
/// embeds this as its bottomNavigationBar — switching tabs replaces the
/// current route (not a stack push), matching normal tab-bar semantics.
class CaregiverBottomNav extends StatelessWidget {
  final int currentIndex;

  const CaregiverBottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) {
        if (index == currentIndex) return;
        final route = index == 0 ? '/profile' : '/jobs';
        Navigator.of(context).pushReplacementNamed(route);
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Jobs'),
      ],
    );
  }
}
