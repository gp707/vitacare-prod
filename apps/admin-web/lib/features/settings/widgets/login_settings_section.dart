import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../login_settings/data/otp_settings_repository.dart';

const _appLabels = {'nursejobs': 'NurseJobs', 'nursenow': 'NurseNow'};
const _appDescriptions = {
  'nursejobs': 'Caregiver registration and login (NurseJobs app).',
  'nursenow': 'Patient/family and hospital/rehab registration and login (NurseNow app).',
};

/// The "Login Settings" tab of the Settings hub — lets an admin force
/// either mobile app onto SMS-OTP registration/login instead of the
/// default phone + 4-digit PIN — additive, not a replacement: while OFF
/// (the default) an app behaves exactly as before. While ON, that app's
/// registration/login screens show phone+OTP only and hide the PIN field
/// entirely. Each app is toggled independently. See
/// AuthService.resolveCredential (apps/api) for how the backend enforces
/// this server-side, never trusting the client.
class LoginSettingsSection extends ConsumerStatefulWidget {
  const LoginSettingsSection({super.key});

  @override
  ConsumerState<LoginSettingsSection> createState() => _LoginSettingsSectionState();
}

class _LoginSettingsSectionState extends ConsumerState<LoginSettingsSection> {
  List<OtpAppSetting> _settings = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final settings = await ref.read(otpSettingsRepositoryProvider).list();
      if (mounted) setState(() => _settings = settings);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(OtpAppSetting setting, bool value) async {
    final index = _settings.indexOf(setting);
    setState(() {
      _settings[index] = OtpAppSetting(
        app: setting.app,
        enabled: value,
        updatedByName: setting.updatedByName,
        updatedAt: setting.updatedAt,
      );
      _errorMessage = null;
    });
    try {
      await ref.read(otpSettingsRepositoryProvider).update(setting.app, value);
      await _load();
    } on ApiException catch (e) {
      // Revert the optimistic flip — the request didn't actually succeed.
      if (mounted) {
        setState(() {
          _settings[index] = setting;
          _errorMessage = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: VitaLoadingIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Force an app onto OTP-based registration and login instead of a 4-digit PIN. '
            'Turning this off reverts that app to the PIN flow immediately.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: AppSpacing.md),
          ],
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      itemCount: _settings.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final setting = _settings[index];
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _appLabels[setting.app] ?? setting.app,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.subtitle),
                    ),
                    const SizedBox(height: 4),
                    Text(_appDescriptions[setting.app] ?? '',
                        style: const TextStyle(color: AppColors.textSecondary)),
                    if (setting.updatedByName != null)
                      Text(
                        'Last updated by ${setting.updatedByName}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
                      ),
                  ],
                ),
              ),
              Switch(
                value: setting.enabled,
                onChanged: (value) => _toggle(setting, value),
              ),
            ],
          ),
        );
      },
    );
  }
}
