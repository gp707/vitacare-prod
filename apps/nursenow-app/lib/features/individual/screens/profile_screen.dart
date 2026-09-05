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

  // Organisation-only — every other org-owned profile field (contact
  // person name reuses _fullNameController above; the rest need their own
  // controllers/state). Previously only admin could edit these.
  final _orgNameController = TextEditingController();
  final _orgAreaController = TextEditingController();
  String? _orgType;
  String? _orgCity;
  bool _savingOrgProfile = false;
  String? _orgProfileError;
  String? _orgProfileSuccess;
  bool _orgProfilePrefilled = false;

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
    _orgNameController.dispose();
    _orgAreaController.dispose();
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

  /// Organisation-only — every org-owned profile field, saved together in
  /// one call. Previously only admin could change these
  /// (PUT /admin/organisations/:id); phone/PIN stay on their own separate
  /// sections below, unaffected.
  Future<void> _saveOrgProfile() async {
    final contactPersonName = _fullNameController.text.trim();
    final organisationName = _orgNameController.text.trim();
    if (!Validators.isValidName(contactPersonName)) {
      setState(() => _orgProfileError = 'Enter a valid contact person name (letters and spaces only)');
      return;
    }
    if (organisationName.isEmpty) {
      setState(() => _orgProfileError = 'Organisation name is required');
      return;
    }
    if (_orgType == null) {
      setState(() => _orgProfileError = 'Select a type of organisation');
      return;
    }
    if (_orgCity == null) {
      setState(() => _orgProfileError = 'Select a city');
      return;
    }
    setState(() {
      _savingOrgProfile = true;
      _orgProfileError = null;
      _orgProfileSuccess = null;
    });
    try {
      final area = _orgAreaController.text.trim();
      await ref.read(organisationRepositoryProvider).updateProfile(
            fullName: contactPersonName,
            organisationName: organisationName,
            organisationType: _orgType,
            city: _orgCity,
            area: area.isEmpty ? null : area,
          );
      await ref.read(sessionProvider.notifier).loadSession();
      if (mounted) setState(() => _orgProfileSuccess = 'Organisation details updated.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _orgProfileError = e.message);
    } finally {
      if (mounted) setState(() => _savingOrgProfile = false);
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
    if (authenticated != null && authenticated.isOrganisation && !_orgProfilePrefilled) {
      _orgProfilePrefilled = true;
      _orgNameController.text = authenticated.organisationName ?? '';
      _orgAreaController.text = authenticated.area ?? '';
      _orgType = authenticated.organisationType;
      _orgCity = authenticated.city;
    }

    return Scaffold(
      appBar: AppBar(
        title: const VitaAppBarTitle('Profile'),
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
                  ] else ...[
                    const Divider(height: AppSpacing.xxl),
                    const Row(
                      children: [
                        Icon(Icons.business, size: 18, color: AppColors.primaryDark),
                        SizedBox(width: AppSpacing.xs),
                        Text('Organisation Details',
                            style: TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(labelText: 'Contact person name'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _orgNameController,
                      decoration: const InputDecoration(labelText: 'Organisation name'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _orgType,
                      decoration: const InputDecoration(labelText: 'Type of organisation'),
                      items: OrganisationType.all
                          .map((t) => DropdownMenuItem(value: t, child: Text(OrganisationType.displayNames[t] ?? t)))
                          .toList(),
                      onChanged: (value) => setState(() => _orgType = value),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _orgCity,
                      decoration: const InputDecoration(labelText: 'City'),
                      items: [
                        ...City.all.map((c) => DropdownMenuItem(value: c, child: Text(City.displayNames[c] ?? c))),
                        const DropdownMenuItem(value: 'others', child: Text('Others')),
                      ],
                      onChanged: (value) => setState(() => _orgCity = value),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _orgAreaController,
                      decoration: const InputDecoration(labelText: 'Area (Optional)'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_orgProfileError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(_orgProfileError!, style: const TextStyle(color: AppColors.error)),
                      ),
                    if (_orgProfileSuccess != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(_orgProfileSuccess!, style: const TextStyle(color: AppColors.success)),
                      ),
                    ElevatedButton.icon(
                      onPressed: _savingOrgProfile ? null : _saveOrgProfile,
                      icon: _savingOrgProfile
                          ? const SizedBox(height: 16, width: 16, child: VitaLoadingIndicator(size: 16))
                          : const Icon(Icons.check, size: 16),
                      label: const Text('Save Organisation Details'),
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
