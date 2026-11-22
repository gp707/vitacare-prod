import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Opens the Patients/Family or Rehab/Hospitals list showing only some accounts — the ones a caregiver is
/// assigned to (the Caregivers status click-through). Passed as the route argument.
class AssignedAccountsFilter {
  final List<String> userIds;
  final String caregiverName;

  const AssignedAccountsFilter({required this.userIds, required this.caregiverName});

  @override
  String toString() => 'AssignedAccountsFilter(${userIds.join(',')}; $caregiverName)';
}

/// "Showing the 2 patients/families Asha is assigned to — Show all". [noun] is e.g. "patients/families".
class AssignedAccountsBanner extends StatelessWidget {
  final AssignedAccountsFilter filter;
  final String noun;
  final VoidCallback onShowAll;

  const AssignedAccountsBanner({super.key, required this.filter, required this.noun, required this.onShowAll});

  @override
  Widget build(BuildContext context) {
    final n = filter.userIds.length;
    return Container(
      key: const Key('assigned-accounts-banner'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.success),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing the ${n == 1 ? '1 $noun' : '$n $noun'} ${filter.caregiverName} is assigned to',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            key: const Key('assigned-accounts-show-all'),
            onPressed: onShowAll,
            child: const Text('Show all'),
          ),
        ],
      ),
    );
  }
}
