import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';

/// Read-only "who applied" view for an individual/organisation reviewing a
/// caregiver applicant — the full profile, same data CaregiverService
/// .getApplicantProfile returns server-side, including email and
/// Aadhaar/qualification/other-document links.
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
                            if (caregiverDisplayId(profile.caregiverNumber) != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                caregiverDisplayId(profile.caregiverNumber)!,
                                style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                              ),
                            ],
                            if (profile.verificationStatus == VerificationStatus.available ||
                                profile.verificationStatus == VerificationStatus.assigned) ...[
                              const SizedBox(height: AppSpacing.xs),
                              const _VerifiedBadge(),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            _InfoCard(profile: profile),
                            const SizedBox(height: AppSpacing.md),
                            _DocumentsCard(profile: profile),
                            if (profile.preferredCities.isNotEmpty ||
                                profile.preferredDutyTypes.isNotEmpty ||
                                profile.minSalaryPerDay != null ||
                                profile.minSalaryPerMonth != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              _PreferencesCard(profile: profile),
                            ],
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
          if (profile.email != null) _InfoRow('Email', profile.email!),
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

class _DocumentsCard extends StatelessWidget {
  final CaregiverProfileModel profile;

  const _DocumentsCard({required this.profile});

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
          const Text('Documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: AppSpacing.xs),
          _DocumentLink('Aadhaar Card', profile.aadhaarDocumentUrl),
          _DocumentLink('Qualification Document', profile.qualificationDocumentUrl),
          for (var i = 0; i < profile.otherDocumentUrls.length; i++)
            _DocumentLink('Other Document ${i + 1}', profile.otherDocumentUrls[i]),
        ],
      ),
    );
  }
}

class _DocumentLink extends StatelessWidget {
  final String label;
  final String? url;

  const _DocumentLink(this.label, this.url);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: url == null
                ? const Text('Not uploaded', style: TextStyle(color: AppColors.textSecondary))
                : TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                    onPressed: () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PreferencesCard extends StatelessWidget {
  final CaregiverProfileModel profile;

  const _PreferencesCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final salaryParts = <String>[
      if (profile.minSalaryPerDay != null) '₹${profile.minSalaryPerDay}/day',
      if (profile.minSalaryPerMonth != null) '₹${profile.minSalaryPerMonth}/month',
    ];
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
          const Text('Job Search Preferences', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: AppSpacing.xs),
          if (profile.preferredCities.isNotEmpty)
            _InfoRow(
              'Preferred Cities',
              profile.preferredCities.map((c) => City.displayNames[c] ?? c).join(', '),
            ),
          if (profile.preferredDutyTypes.isNotEmpty)
            _InfoRow(
              'Hours Care Needed',
              profile.preferredDutyTypes.map((d) => DutyType.displayNames[d] ?? d).join(', '),
            ),
          if (salaryParts.isNotEmpty) _InfoRow('Min. Salary', salaryParts.join(', ')),
        ],
      ),
    );
  }
}

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
