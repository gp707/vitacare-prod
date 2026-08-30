import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/nursenow_bottom_nav.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../app/rate_card_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
import '../../auth/state/session_state.dart';

/// Identity + self-service account settings — shared by both Individual and
/// Organisation accounts (branches internally on `session.isOrganisation`
/// for which repository's phone/code endpoints to call, and for a couple
/// of organisation-only display fields). No verification pipeline to show
/// (neither account type has one) — just who's logged in, whether job-
/// posting is currently blocked, and phone/PIN change, each an
/// independently-saved section (same pattern as caregiver-app's
/// EditProfileScreen) since they map to two different backend endpoints.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _phoneController = TextEditingController();
  bool _savingPhone = false;
  String? _phoneError;
  String? _phoneSuccess;

  final _codeController = TextEditingController();
  bool _savingCode = false;
  String? _codeError;
  String? _codeSuccess;

  bool _phonePrefilled = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _savePhone(bool isOrganisation) async {
    final phone = _phoneController.text.trim();
    if (!Validators.isValidPhone(phone)) {
      setState(() => _phoneError = 'Enter a valid phone number, e.g. +919876543210');
      return;
    }
    setState(() {
      _savingPhone = true;
      _phoneError = null;
      _phoneSuccess = null;
    });
    try {
      if (isOrganisation) {
        await ref.read(organisationRepositoryProvider).updatePhone(phone);
      } else {
        await ref.read(individualRepositoryProvider).updatePhone(phone);
      }
      await ref.read(sessionProvider.notifier).loadSession();
      if (mounted) setState(() => _phoneSuccess = 'Phone number updated.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _phoneError = e.message);
    } finally {
      if (mounted) setState(() => _savingPhone = false);
    }
  }

  Future<void> _saveCode(bool isOrganisation) async {
    final code = _codeController.text.trim();
    if (!Validators.isValidCode(code)) {
      setState(() => _codeError = 'PIN must be exactly 4 digits');
      return;
    }
    setState(() {
      _savingCode = true;
      _codeError = null;
      _codeSuccess = null;
    });
    try {
      if (isOrganisation) {
        await ref.read(organisationRepositoryProvider).updateCode(code);
      } else {
        await ref.read(individualRepositoryProvider).updateCode(code);
      }
      if (mounted) {
        _codeController.clear();
        setState(() => _codeSuccess = 'PIN updated.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _codeError = e.message);
    } finally {
      if (mounted) setState(() => _savingCode = false);
    }
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await ref.read(sessionProvider.notifier).logout();
    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final authenticated = session is SessionAuthenticated ? session : null;

    // Prefill the phone field from the session once, the first time it's
    // available — a plain setState during build (not initState) since the
    // session hydrates asynchronously and may not be ready on first build.
    if (authenticated != null && !_phonePrefilled) {
      _phonePrefilled = true;
      _phoneController.text = authenticated.phone;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: const [RateCardButton(), WhatsAppHelpButton()],
      ),
      backgroundColor: AppColors.background,
      bottomNavigationBar: const NurseNowBottomNav(currentIndex: 0),
      body: authenticated == null
          ? const Center(child: VitaLoadingIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    authenticated.isOrganisation ? authenticated.organisationName! : authenticated.fullName,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if ((authenticated.isOrganisation
                          ? organisationDisplayId(authenticated.orgNumber)
                          : patientDisplayId(authenticated.patientNumber)) !=
                      null) ...[
                    const SizedBox(height: 2),
                    Text(
                      (authenticated.isOrganisation
                          ? organisationDisplayId(authenticated.orgNumber)
                          : patientDisplayId(authenticated.patientNumber))!,
                      style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (authenticated.isOrganisation) ...[
                    const SizedBox(height: 2),
                    Text('Contact: ${authenticated.fullName}', style: const TextStyle(color: AppColors.textSecondary)),
                    Text(
                      [
                        OrganisationType.displayNames[authenticated.organisationType] ?? authenticated.organisationType!,
                        City.displayNames[authenticated.city] ?? authenticated.city!,
                        authenticated.area!,
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(authenticated.phone, style: const TextStyle(color: AppColors.textSecondary)),
                  if (authenticated.isJobPostingBlocked) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Posting new requirements is currently blocked. Contact the office for details.',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ],
                  const Divider(height: AppSpacing.xxl),
                  const Text('Phone Number', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: 'Phone number', errorText: _phoneError),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_phoneSuccess != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(_phoneSuccess!, style: const TextStyle(color: AppColors.success)),
                    ),
                  ElevatedButton(
                    onPressed: _savingPhone ? null : () => _savePhone(authenticated.isOrganisation),
                    child: _savingPhone
                        ? const SizedBox(height: 16, width: 16, child: VitaLoadingIndicator(size: 16))
                        : const Text('Save Phone Number'),
                  ),
                  const Divider(height: AppSpacing.xxl),
                  const Text('Login PIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    decoration: InputDecoration(labelText: 'New 4-digit PIN', errorText: _codeError),
                  ),
                  if (_codeSuccess != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(_codeSuccess!, style: const TextStyle(color: AppColors.success)),
                    ),
                  ElevatedButton(
                    onPressed: _savingCode ? null : () => _saveCode(authenticated.isOrganisation),
                    child: _savingCode
                        ? const SizedBox(height: 16, width: 16, child: VitaLoadingIndicator(size: 16))
                        : const Text('Save PIN'),
                  ),
                  const Divider(height: AppSpacing.xxl),
                  OutlinedButton(onPressed: _logout, child: const Text('Logout')),
                ],
              ),
            ),
    );
  }
}
