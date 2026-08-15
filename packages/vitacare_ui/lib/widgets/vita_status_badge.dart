import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

const Map<String, String> _statusLabels = {
  VerificationStatus.pendingCall: 'Pending Call',
  VerificationStatus.available: 'Available',
  VerificationStatus.unavailable: 'Unavailable',
  VerificationStatus.assigned: 'Assigned',
  VerificationStatus.rejected: 'Rejected',
};

const Map<String, Color> _statusColors = {
  VerificationStatus.pendingCall: AppColors.statusPendingCall,
  VerificationStatus.available: AppColors.statusAvailable,
  VerificationStatus.unavailable: AppColors.textSecondary,
  VerificationStatus.assigned: AppColors.statusAssigned,
  VerificationStatus.rejected: AppColors.statusRejected,
};

/// Renders a caregiver's [VerificationStatus] consistently across the
/// caregiver app and admin dashboard.
class VitaStatusBadge extends StatelessWidget {
  final String status;

  const VitaStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status] ?? AppColors.textSecondary;
    final label = _statusLabels[status] ?? status;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
