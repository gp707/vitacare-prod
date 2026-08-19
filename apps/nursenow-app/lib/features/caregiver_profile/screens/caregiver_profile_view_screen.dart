import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';

/// Read-only "who applied" view for an individual/organisation reviewing a
/// caregiver applicant. Deliberately lean — see
/// CaregiverService.getApplicantProfile server-side for what's
/// intentionally left out (no email, no Aadhaar/qualification-document
/// links, no job-search preferences) so this stays a quick, clean glance
/// rather than a crowded document viewer.
class CaregiverProfileViewScreen extends StatefulWidget {
  final Future<CaregiverProfileModel> Function() fetchProfile;

  const CaregiverProfileViewScreen({super.key, required this.fetchProfile});

  @override
  State<CaregiverProfileViewScreen> createState() => _CaregiverProfileViewScreenState();
}

class _CaregiverProfileViewScreenState extends State<CaregiverProfileViewScreen> {
  CaregiverProfileModel? _profile;
  String? _errorMessage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final profile = await widget.fetchProfile();
      if (mounted) setState(() => _profile = profile);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: Text(profile?.fullName ?? 'Caregiver Profile')),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: VitaLoadingIndicator())
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
                    ),
                  )
                : profile == null
                    ? const SizedBox.shrink()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            _Avatar(url: profile.selfiePhotoUrl),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              profile.fullName,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            if (profile.verificationStatus == VerificationStatus.available ||
                                profile.verificationStatus == VerificationStatus.assigned) ...[
                              const SizedBox(height: AppSpacing.xs),
                              const _VerifiedBadge(),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            _InfoCard(profile: profile),
                          ],
                        ),
                      ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;

  const _Avatar({required this.url});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 48,
      backgroundColor: AppColors.primaryLight,
      backgroundImage: url != null ? NetworkImage(url!) : null,
      child: url == null ? const Icon(Icons.person, size: 48, color: AppColors.primary) : null,
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: AppColors.success),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 14, color: AppColors.success),
          SizedBox(width: 4),
          Text(
            'VitaCare-verified caregiver',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final CaregiverProfileModel profile;

  const _InfoCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow('Phone', profile.phone),
          _InfoRow('Age', '${profile.age} yrs'),
          _InfoRow('Gender', capitalize(profile.gender)),
          if (profile.highestQualification != null)
            _InfoRow(
              'Qualification',
              Qualification.displayNames[profile.highestQualification!] ?? profile.highestQualification!,
            ),
          if (profile.religion != null) _InfoRow('Religion', Religion.displayNames[profile.religion!] ?? profile.religion!),
          if (profile.languages.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text('Languages', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final language in profile.languages)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                    ),
                    child: Text(Language.displayNames[language] ?? language, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
