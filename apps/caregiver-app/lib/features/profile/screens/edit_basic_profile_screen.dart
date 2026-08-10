import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';

const _reReviewStatuses = [VerificationStatus.available, VerificationStatus.unavailable];

/// Full Name and Gender are deliberately not editable here — only admins
/// can change them once set at registration. Age/Languages, Phone, and PIN
/// are three independently-saved sections since they map to three
/// different backend endpoints with different review-trigger semantics
/// (phone can send an available/unavailable caregiver back for re-review;
/// the rest never do).
class EditBasicProfileScreen extends ConsumerStatefulWidget {
  const EditBasicProfileScreen({super.key});

  @override
  ConsumerState<EditBasicProfileScreen> createState() => _EditBasicProfileScreenState();
}

class _EditBasicProfileScreenState extends ConsumerState<EditBasicProfileScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  CaregiverProfileModel? _profile;
  bool _loading = true;
  final List<String> _languages = [];
  late final TextEditingController _ageController;

  bool _savingBasic = false;
  bool _savingPhone = false;
  bool _savingCode = false;
  String? _basicError;
  String? _phoneError;
  String? _codeError;
  String? _basicSuccess;
  String? _phoneSuccess;
  String? _codeSuccess;

  @override
  void initState() {
    super.initState();
    _ageController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await ref.read(profileRepositoryProvider).getProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _ageController.text = '${profile.age}';
      _languages
        ..clear()
        ..addAll(profile.languages);
      _phoneController.text = profile.phone.replaceFirst('+91', '');
      _loading = false;
    });
  }

  bool get _phoneWillTriggerReview =>
      _profile != null && _reReviewStatuses.contains(_profile!.verificationStatus);

  Future<void> _saveBasic() async {
    setState(() {
      _savingBasic = true;
      _basicError = null;
      _basicSuccess = null;
    });
    try {
      final age = int.tryParse(_ageController.text.trim());
      if (age == null || !Validators.isValidAge(age)) {
        setState(() => _basicError = 'Age must be between ${Validation.ageMin} and ${Validation.ageMax}');
        return;
      }
      if (_languages.isEmpty) {
        setState(() => _basicError = 'Select at least one language');
        return;
      }
      await ref.read(profileRepositoryProvider).updateBasic(
            age: age,
            languages: _languages,
          );
      setState(() => _basicSuccess = 'Saved. Your admin will see this change flagged for review.');
    } on ApiException catch (e) {
      setState(() => _basicError = e.message);
    } finally {
      if (mounted) setState(() => _savingBasic = false);
    }
  }

  Future<void> _savePhone() async {
    final phone = '+91${_phoneController.text.trim()}';
    if (!Validators.isValidPhone(phone)) {
      setState(() => _phoneError = 'Enter a valid 10-digit mobile number');
      return;
    }
    setState(() {
      _savingPhone = true;
      _phoneError = null;
      _phoneSuccess = null;
    });
    try {
      final wasReReviewed = _phoneWillTriggerReview;
      await ref.read(profileRepositoryProvider).updatePhone(phone);
      await ref.read(sessionProvider.notifier).refreshStatus();
      setState(() {
        _phoneSuccess = wasReReviewed
            ? 'Phone updated. Your profile has been sent back for re-review.'
            : 'Phone updated.';
      });
      await _load();
    } on ApiException catch (e) {
      setState(() => _phoneError = e.message);
    } finally {
      if (mounted) setState(() => _savingPhone = false);
    }
  }

  Future<void> _saveCode() async {
    final code = _codeController.text.trim();
    if (!Validators.isValidCode(code)) {
      setState(() => _codeError = 'Code must be exactly 4 digits');
      return;
    }
    setState(() {
      _savingCode = true;
      _codeError = null;
      _codeSuccess = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateCode(code);
      setState(() {
        _codeSuccess = 'Login code updated.';
        _codeController.clear();
      });
    } on ApiException catch (e) {
      setState(() => _codeError = e.message);
    } finally {
      if (mounted) setState(() => _savingCode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Basic Profile')),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: VitaLoadingIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                    ),
                    child: const Text(
                      "Changes here will be reviewed by admin. Your current verification status is not affected — except changing your phone number, which sends an available/unavailable profile back for re-review.",
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Full Name', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_profile?.fullName ?? '', style: const TextStyle(color: AppColors.textSecondary)),
                  const Text(
                    "Contact the office to change your name.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Gender', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _profile != null
                        ? _profile!.gender[0].toUpperCase() + _profile!.gender.substring(1)
                        : '',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const Text(
                    "Contact the office to change your gender.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Age & Languages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Languages', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  VitaMultiSelectChips(
                    options: Language.all,
                    labels: Language.displayNames,
                    selected: _languages,
                    onChanged: (next) => setState(() {
                      _languages
                        ..clear()
                        ..addAll(next);
                    }),
                  ),
                  if (_basicError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_basicError!, style: const TextStyle(color: AppColors.error)),
                  ],
                  if (_basicSuccess != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_basicSuccess!, style: const TextStyle(color: AppColors.success)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _savingBasic ? null : _saveBasic,
                    child: _savingBasic ? const _ButtonSpinner() : const Text('Save'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text('Phone Number', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.sm),
                  if (_phoneWillTriggerReview)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppSpacing.sm),
                      ),
                      child: const Text(
                        'Changing your phone number will send your profile back for re-review.',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      prefixText: '+91 ',
                      labelText: 'Phone number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_phoneError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_phoneError!, style: const TextStyle(color: AppColors.error)),
                  ],
                  if (_phoneSuccess != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_phoneSuccess!, style: const TextStyle(color: AppColors.success)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _savingPhone ? null : _savePhone,
                    child: _savingPhone ? const _ButtonSpinner() : const Text('Save Phone Number'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text('Login PIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    "Changing your PIN never affects your verification status.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New 4-Digit PIN', border: OutlineInputBorder()),
                  ),
                  if (_codeError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_codeError!, style: const TextStyle(color: AppColors.error)),
                  ],
                  if (_codeSuccess != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_codeSuccess!, style: const TextStyle(color: AppColors.success)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _savingCode ? null : _saveCode,
                    child: _savingCode ? const _ButtonSpinner() : const Text('Save PIN'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}
