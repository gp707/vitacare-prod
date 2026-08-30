import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
import '../status_message.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../app/rate_card_button.dart';

/// Full read-only view of the caregiver's own profile, reachable at any
/// verification status. The single Edit entry point hands off to
/// EditProfileScreen — editing while rejected auto-resubmits server-side,
/// so there's no separate "Edit & Resubmit" flow to route to.
class ProfileViewScreen extends ConsumerStatefulWidget {
  const ProfileViewScreen({super.key});

  @override
  ConsumerState<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

// 'assigned' is deliberately not here — a caregiver can hold several
// accepted jobs at once, and this button can't say which one it means.
// MyJobs' per-job "Mark Complete" is the only way out of `assigned` now.
const _kMarkAvailableEligibleStatuses = ['available', 'unavailable'];

class _ProfileViewScreenState extends ConsumerState<ProfileViewScreen> {
  CaregiverProfileModel? _profile;
  bool _loading = true;
  bool _markingAvailable = false;
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

  Future<void> _markAvailable() async {
    if (_profile == null || _markingAvailable) return;

    if (_profile!.verificationStatus == 'available') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are already marked as available')),
      );
      return;
    }

    setState(() => _markingAvailable = true);
    try {
      await ref.read(profileRepositoryProvider).markAvailable();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You're now marked as available")),
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _markingAvailable = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          const RateCardButton(),
          const WhatsAppHelpButton(),
          TextButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              ref.read(sessionProvider.notifier).logout().then((_) {
                navigator.pushNamedAndRemoveUntil('/login', (route) => false);
              });
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
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
        if (_kMarkAvailableEligibleStatuses.contains(profile.verificationStatus)) ...[
          const SizedBox(height: AppSpacing.md),
          Center(
            child: ElevatedButton(
              onPressed: _markingAvailable ? null : _markAvailable,
              child: _markingAvailable
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Available for Jobs'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Basic Info',
          onEdit: () => Navigator.of(context).pushNamed('/profile/edit').then((_) => _load()),
          children: [
            _Field('Full Name', profile.fullName),
            _Field('Phone', profile.phone),
            _Field('Gender', profile.gender[0].toUpperCase() + profile.gender.substring(1)),
            _Field('Age', '${profile.age}'),
            _Field('Languages', profile.languages.map((l) => Language.displayNames[l] ?? l).join(', ')),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Professional & Contact Info',
          onEdit: () => Navigator.of(context).pushNamed('/profile/edit').then((_) => _load()),
          children: [
            _Field('Qualification', Qualification.displayNames[profile.highestQualification] ?? '—'),
            _Field('Religion', Religion.displayNames[profile.religion] ?? '—'),
            _Field(
              'Preferred City',
              profile.preferredCities.isEmpty
                  ? '—'
                  : profile.preferredCities.map((c) => City.displayNames[c] ?? c).join(', '),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Documents',
          onEdit: () => Navigator.of(context).pushNamed('/profile/edit').then((_) => _load()),
          children: [
            _Field('Selfie', profile.selfiePhotoUrl != null ? 'Uploaded' : 'Not uploaded'),
            _Field('Aadhaar Card', profile.aadhaarDocumentUrl != null ? 'Uploaded' : 'Not uploaded'),
            _Field(
              'Qualification Document',
              profile.qualificationDocumentUrl != null ? 'Uploaded' : 'Not uploaded',
            ),
            _Field('Other Documents', '${profile.otherDocumentUrls.length} uploaded'),
          ],
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
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (onEdit != null) TextButton(onPressed: onEdit, child: const Text('Edit')),
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
  final String label;
  final String value;

  const _Field(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
