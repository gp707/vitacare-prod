import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/auth_result.dart';
import '../state/session_notifier.dart';
import '../state/session_state.dart';

enum _AccountType { individual, organisation }

/// Flow: phone -> PIN -> account type -> (Individual: done; Organisation:
/// a later phase — org name/contact person/type/city/area, not built yet).
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _fullNameController = TextEditingController();
  _AccountType? _accountType;
  bool _loading = false;
  String? _errorMessage;

  String get _phone => '+91${_phoneController.text.trim()}';

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!Validators.isValidPhone(_phone)) {
      setState(() => _errorMessage = 'Enter a valid 10-digit mobile number');
      return;
    }
    if (!Validators.isValidCode(_codeController.text.trim())) {
      setState(() => _errorMessage = 'Enter a 4-digit PIN');
      return;
    }
    if (_fullNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Enter your full name');
      return;
    }
    if (_accountType == null) {
      setState(() => _errorMessage = 'Select an account type');
      return;
    }
    if (_accountType == _AccountType.organisation) {
      setState(() => _errorMessage = 'Hospital/Rehab registration is coming soon.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final AuthResult result = await authRepo.register(
        phone: _phone,
        fullName: _fullNameController.text.trim(),
        code: _codeController.text.trim(),
      );
      final localStorage = ref.read(localStorageProvider);
      await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
      await ref.read(sessionProvider.notifier).loadSession();
      if (!mounted) return;
      final session = ref.read(sessionProvider);
      if (session is SessionAuthenticated) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                prefixText: '+91 ',
                labelText: 'Phone number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Create a 4-digit PIN',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Account type', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            RadioListTile<_AccountType>(
              title: const Text('Individual'),
              subtitle: const Text('Patient, or a family member/caregiver acting on their behalf'),
              value: _AccountType.individual,
              groupValue: _accountType,
              onChanged: (value) => setState(() => _accountType = value),
            ),
            RadioListTile<_AccountType>(
              title: const Text('Hospital / Rehab'),
              subtitle: const Text('Coming soon'),
              value: _AccountType.organisation,
              groupValue: _accountType,
              onChanged: (value) => setState(() => _accountType = value),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }
}
