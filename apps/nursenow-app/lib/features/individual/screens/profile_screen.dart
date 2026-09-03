import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/messages_bell.dart';
import '../../../app/nursenow_bottom_nav.dart';
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
  final _fullNameController = TextEditingController();
  bool _savingName = false;
  String? _nameError;
  String? _nameSuccess;

  final _phoneController = TextEditingController();
  bool _savingPhone = false;
  String? _phoneError;
  String? _phoneSuccess;

  final _codeController = TextEditingController();
  bool _savingCode = false;
  String? _codeError;
  String? _codeSuccess;

  bool _namePrefilled = false;
  bool _phonePrefilled = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Individual-only — unlike a caregiver's full_name (locked from
  /// self-edit — only admins can change it), a patient/family account can
  /// freely update their own name. Not offered for Organisation (the
  /// "contact person" name is admin-editable via a different flow, see
  /// CLAUDE.md — out of scope here since it wasn't asked for).
  Future<void> _saveName() async {
    final name = _fullNameController.text.trim();
    if (!Validators.isValidName(name)) {
      setState(() => _nameError = 'Enter a valid name (letters and spaces only)');
      return;
    }
    setState(() {
      _savingName = true;
      _nameError = null;
      _nameSuccess = null;
    });
    try {
      await ref.read(individualRepositoryProvider).updateName(name);
      await ref.read(sessionProvider.notifier).loadSession();
      if (mounted) setState(() => _nameSuccess = 'Name updated.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _nameError = e.message);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
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

    // Prefill the name/phone fields from the session once, the first time
    // they're available — a plain setState during build (not initState)
    // since the session hydrates asynchronously and may not be ready on
    // first build.
    if (authenticated != null && !_namePrefilled) {
      _namePrefilled = true;
      _fullNameController.text = authenticated.fullName;
    }
    if (authenticated != null && !_phonePrefilled) {
      _phonePrefilled = true;
      _phoneController.text = authenticated.phone;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: individualAppBarActions(showBell: !(session is SessionAuthenticated && session.isOrganisation)),
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
                    style: const TextStyle(fontSize: AppTypography.heading, fontWeight: FontWeight.bold),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(authenticated.phone, style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                  if (authenticated.isJobPostingBlocked) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Posting new requirements is currently blocked. Contact the office for details.',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ],
                  if (!authenticated.isOrganisation) ...[
                    const Divider(height: AppSpacing.xxl),
                    const Row(
                      children: [
                        Icon(Icons.badge, size: 18, color: AppColors.primaryDark),
                        SizedBox(width: AppSpacing.xs),
                        Text('Full Name', style: TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _fullNameController,
                      decoration: InputDecoration(labelText: 'Full name', errorText: _nameError),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_nameSuccess != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(_nameSuccess!, style: const TextStyle(color: AppColors.success)),
                      ),
                    ElevatedButton.icon(
                      onPressed: _savingName ? null : _saveName,
                      icon: _savingName
                          ? const SizedBox(height: 16, width: 16, child: VitaLoadingIndicator(size: 16))
                          : const Icon(Icons.check, size: 16),
                      label: const Text('Save Name'),
                    ),
                  ],
                  const Divider(height: AppSpacing.xxl),
                  const Row(
                    children: [
                      Icon(Icons.phone, size: 18, color: AppColors.primaryDark),
                      SizedBox(width: AppSpacing.xs),
                      Text('Phone Number', style: TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold)),
                    ],
                  ),
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
                  ElevatedButton.icon(
                    onPressed: _savingPhone ? null : () => _savePhone(authenticated.isOrganisation),
                    icon: _savingPhone
                        ? const SizedBox(height: 16, width: 16, child: VitaLoadingIndicator(size: 16))
                        : const Icon(Icons.check, size: 16),
                    label: const Text('Save Phone Number'),
                  ),
                  const Divider(height: AppSpacing.xxl),
                  const Row(
                    children: [
                      Icon(Icons.lock_outline, size: 18, color: AppColors.primaryDark),
                      SizedBox(width: AppSpacing.xs),
                      Text('Login PIN', style: TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold)),
                    ],
                  ),
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
                  ElevatedButton.icon(
                    onPressed: _savingCode ? null : () => _saveCode(authenticated.isOrganisation),
                    icon: _savingCode
                        ? const SizedBox(height: 16, width: 16, child: VitaLoadingIndicator(size: 16))
                        : const Icon(Icons.check, size: 16),
                    label: const Text('Save PIN'),
                  ),
                  const Divider(height: AppSpacing.xxl),
                  OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, size: 16, color: AppColors.error),
                    label: const Text('Logout', style: TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error)),
                  ),
                ],
              ),
            ),
    );
  }
}
