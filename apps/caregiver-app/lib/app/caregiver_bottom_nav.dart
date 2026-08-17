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
    const routes = ['/profile', '/jobs', '/my-jobs'];
    return BottomNavigationBar(
      currentIndex: currentIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        if (index == currentIndex) return;
        Navigator.of(context).pushReplacementNamed(routes[index]);
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Jobs'),
        BottomNavigationBarItem(icon: Icon(Icons.assignment_ind), label: 'MyJobs'),
      ],
    );
  }
}
