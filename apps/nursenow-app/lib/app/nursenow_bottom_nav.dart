import 'package:flutter/material.dart';

/// Mirrors NurseJobs (caregiver-app)'s CaregiverBottomNav pattern — each
/// screen owns its own Scaffold/AppBar and just embeds this as its
/// bottomNavigationBar. Two tabs: Profile (identity + phone/PIN self-edit)
/// and Jobs Posted (the account's requirement history + post-a-requirement
/// entry point).
class NurseNowBottomNav extends StatelessWidget {
  final int currentIndex;

  const NurseNowBottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    const routes = ['/profile', '/home'];
    return BottomNavigationBar(
      currentIndex: currentIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        if (index == currentIndex) return;
        Navigator.of(context).pushReplacementNamed(routes[index]);
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Jobs Posted'),
      ],
    );
  }
}
