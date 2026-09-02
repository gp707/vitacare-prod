import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';

/// The "General" tab of the Settings hub: the apply-by urgency window (how
/// many days a job stays flagged "new"/urgent to caregivers before showing
/// "Application window closed" — purely cosmetic, does not auto-hide or
/// auto-close the job itself, admin must still act on it manually, see
/// AdminJobsScreen's "posted more than N days ago" filter) plus a
/// self-service password-change form for the logged-in admin.
class GeneralSettingsSection extends ConsumerStatefulWidget {
  const GeneralSettingsSection({super.key});

  @override
  ConsumerState<GeneralSettingsSection> createState() => _GeneralSettingsSectionState();
}

class _GeneralSettingsSectionState extends ConsumerState<GeneralSettingsSection> {
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;
  String? _updatedByName;
  String? _updatedAt;
  late TextEditingController _windowDaysController;

  @override
  void initState() {
    super.initState();
    _windowDaysController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _windowDaysController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final settings = await ref.read(jobSettingsRepositoryProvider).get();
      if (!mounted) return;
      setState(() {
        _windowDaysController.text = settings.applyByWindowDays.toString();
        _updatedByName = settings.updatedByName;
        _updatedAt = settings.updatedAt;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final days = int.tryParse(_windowDaysController.text.trim());
    if (days == null || days < 1) {
      setState(() => _errorMessage = 'Enter a whole number of at least 1');
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await ref.read(jobSettingsRepositoryProvider).update(days);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Apply-by window saved')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: VitaLoadingIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          _SectionCard(
            icon: Icons.hourglass_bottom,
            title: 'Apply-By Window',
            description:
                'How many days a job stays in its "new"/urgent apply-by window before caregivers '
                'see "Application window closed". Purely informational — it does not hide or close '
                'the job automatically; use the Jobs screen\'s "posted more than N days ago" filter '
                'to find and act on stale jobs.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _windowDaysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Days',
                      prefixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_updatedByName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      'Last updated by $_updatedByName${_updatedAt != null ? ' on $_updatedAt' : ''}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _ChangePasswordCard(),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 18, color: AppColors.primaryDark),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: const TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small)),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _ChangePasswordCard extends ConsumerStatefulWidget {
  const _ChangePasswordCard();

  @override
  ConsumerState<_ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends ConsumerState<_ChangePasswordCard> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
    if (_currentController.text.isEmpty) {
      setState(() => _errorMessage = 'Enter your current password');
      return;
    }
    if (_newController.text.length < Validation.passwordMinLength) {
      setState(() => _errorMessage =
          'New password must be at least ${Validation.passwordMinLength} characters');
      return;
    }
    if (_newController.text != _confirmController.text) {
      setState(() => _errorMessage = 'New password and confirmation do not match');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(adminProfileRepositoryProvider).changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (mounted) {
        _currentController.clear();
        _newController.clear();
        _confirmController.clear();
        setState(() => _successMessage = 'Password changed');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.lock_outline,
      title: 'Change Password',
      description: 'Update the password used to sign in to this admin account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_successMessage != null) ...[
            Text(_successMessage!, style: const TextStyle(color: AppColors.success)),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(
            controller: _currentController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Current Password',
              prefixIcon: Icon(Icons.lock_outline, size: 18),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _newController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New Password',
              prefixIcon: Icon(Icons.lock, size: 18),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _confirmController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm New Password',
              prefixIcon: Icon(Icons.lock, size: 18),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, size: 18),
            label: const Text('Change Password'),
          ),
        ],
      ),
    );
  }
}
