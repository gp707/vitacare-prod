import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
import '../status_message.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../app/messages_bell.dart';

/// Full read-only view of the caregiver's own profile, reachable at any
/// verification status. The single Edit entry point hands off to
/// EditProfileScreen — editing while rejected auto-resubmits server-side,
/// so there's no separate "Edit & Resubmit" flow to route to.
class ProfileViewScreen extends ConsumerStatefulWidget {
  const ProfileViewScreen({super.key});

  @override
  ConsumerState<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends ConsumerState<ProfileViewScreen> {
  CaregiverProfileModel? _profile;
  bool _loading = true;
  String? _errorMessage;

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
      final profile = await ref.read(profileRepositoryProvider).getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await ref.read(sessionProvider.notifier).logout();
    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: caregiverAppBarActions(showBell: true),
      ),
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CaregiverBottomNav(currentIndex: 0),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: VitaLoadingIndicator())
              : _errorMessage != null
                  ? ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
                      ],
                    )
                  : _buildContent(context, _profile!),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, CaregiverProfileModel profile) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Center(child: VitaStatusBadge(status: profile.verificationStatus)),
        if (caregiverDisplayId(profile.caregiverNumber) != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              caregiverDisplayId(profile.caregiverNumber)!,
              style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          statusMessageFor(profile.verificationStatus, profile.rejectionMessage),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Basic Info',
          onEdit: () => Navigator.of(context).pushNamed('/profile/edit').then((_) => _load()),
          children: [
            _Field(Icons.badge, 'Full Name', profile.fullName),
            _Field(Icons.phone, 'Phone', profile.phone),
            _Field(Icons.wc, 'Gender', profile.gender[0].toUpperCase() + profile.gender.substring(1)),
            _Field(Icons.cake, 'Age', '${profile.age}'),
            _Field(
              Icons.language,
              'Languages',
              profile.languages.map((l) => Language.displayNames[l] ?? l).join(', '),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Professional & Contact Info',
          onEdit: () => Navigator.of(context).pushNamed('/profile/edit').then((_) => _load()),
          children: [
            _Field(Icons.school, 'Qualification', Qualification.displayNames[profile.highestQualification] ?? '—'),
            _Field(Icons.diversity_3, 'Religion', Religion.displayNames[profile.religion] ?? '—'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Documents',
          onEdit: () => Navigator.of(context).pushNamed('/profile/edit').then((_) => _load()),
          children: [
            _Field(
              Icons.camera_alt,
              'Selfie',
              profile.selfiePhotoUrl != null ? 'Uploaded' : 'Not uploaded',
              valueColor: profile.selfiePhotoUrl != null ? AppColors.success : AppColors.textSecondary,
            ),
            _Field(
              Icons.credit_card,
              'Aadhaar Card',
              profile.aadhaarDocumentUrl != null ? 'Uploaded' : 'Not uploaded',
              valueColor: profile.aadhaarDocumentUrl != null ? AppColors.success : AppColors.textSecondary,
            ),
            _Field(
              Icons.description,
              'Qualification Document',
              profile.qualificationDocumentUrl != null ? 'Uploaded' : 'Not uploaded',
              valueColor: profile.qualificationDocumentUrl != null ? AppColors.success : AppColors.textSecondary,
            ),
            _Field(
              Icons.attach_file,
              'Other Documents',
              '${profile.otherDocumentUrls.length} uploaded',
              valueColor: profile.otherDocumentUrls.isNotEmpty ? AppColors.success : AppColors.textSecondary,
            ),
          ],
        ),
        const Divider(height: AppSpacing.xxl),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout, size: 16, color: AppColors.error),
          label: const Text('Logout', style: TextStyle(color: AppColors.error)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error)),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final VoidCallback? onEdit;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.onEdit,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.error, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: AppTypography.subtitle,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success)),
              ),
              if (onEdit != null)
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 15),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _Field(this.icon, this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(right: AppSpacing.xs),
            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 13, color: AppColors.primaryDark),
          ),
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor ?? AppColors.success, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
