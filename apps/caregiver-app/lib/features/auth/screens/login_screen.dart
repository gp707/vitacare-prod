import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/auth_result.dart';
import '../state/session_notifier.dart';
import '../state/session_state.dart';
import '../../../app/route_for_status.dart';

/// Every caregiver sets their 4-digit code at registration (SPEC.md 3.1
/// Stage 1), so login always requires phone + code — there's no more
/// phone-only fallback / AUTH_012 two-step dance.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  String get _phone => '+91${_phoneController.text.trim()}';

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!Validators.isValidPhone(_phone)) {
      setState(() => _errorMessage = 'Enter a valid 10-digit mobile number');
      return;
    }
    if (!Validators.isValidCode(_codeController.text.trim())) {
      setState(() => _errorMessage = 'Enter the 4-digit code');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final AuthResult result = await authRepo.loginCode(_phone, _codeController.text.trim());
      await _onLoggedIn(result);
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onLoggedIn(AuthResult result) async {
    final localStorage = ref.read(localStorageProvider);
    await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
    await ref.read(sessionProvider.notifier).loadSession();
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    if (session is SessionAuthenticated) {
      Navigator.of(context).pushNamedAndRemoveUntil(routeForStatus(session), (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'VitaCare',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.xl),
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
                  labelText: '4-digit code',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
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
                    : const Text('Login'),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/register'),
                child: const Text('New here? Register'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
