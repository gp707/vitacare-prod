import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/auth_result.dart';
import '../state/session_notifier.dart';
import '../state/session_state.dart';
import '../../../caregiver/core/providers.dart' as caregiver;
import '../../../caregiver/core/network/api_exception.dart' as caregiver_net;
import '../../../caregiver/app/route_for_status.dart' as caregiver_route;
import '../../../caregiver/features/auth/data/auth_result.dart' as caregiver_auth;
import '../../../caregiver/features/auth/state/session_notifier.dart' as caregiver_session;
import '../../../caregiver/features/auth/state/session_state.dart' as caregiver_session_state;

/// Every individual/organisation account sets their 4-digit code at
/// registration, so login always requires phone + code — same mechanism as
/// caregiver login (same backend endpoint, POST /auth/login/code).
///
/// EXCEPT when an admin has enabled OTP mode for this app (see
/// core/providers.dart's otpModeProvider, set once at splash time from
/// GET /auth/otp-settings): the PIN field is then replaced entirely by a
/// phone -> send OTP -> verify two-step flow. otpModeProvider defaults to
/// false and fails open to it on any error, so this screen renders exactly
/// as it always has unless an admin has explicitly turned OTP mode on.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _errorMessage;

  String get _phone => '+91${_phoneController.text.trim()}';

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submitPin() async {
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
      // AUTH_002 ("no account found with this phone number") means this
      // phone definitely isn't a nursenow (individual/organisation)
      // account — now that phone numbers are globally unique across every
      // registration-facing role (see CLAUDE.md), it's safe to retry as a
      // caregiver login instead of surfacing the error. Any other code
      // (wrong PIN, AUTH_004 deactivated, etc.) surfaces exactly as before.
      if (e.code == 'AUTH_002') {
        await _tryCaregiverLogin();
      } else {
        setState(() => _errorMessage = e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _tryCaregiverLogin() async {
    try {
      final authRepo = ref.read(caregiver.authRepositoryProvider);
      final result = await authRepo.loginCode(_phone, _codeController.text.trim());
      await _onCaregiverLoggedIn(result);
    } on caregiver_net.ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    }
  }

  Future<void> _sendOtp() async {
    if (!Validators.isValidPhone(_phone)) {
      setState(() => _errorMessage = 'Enter a valid 10-digit mobile number');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendOtp(phone: _phone, purpose: OtpPurpose.login);
      if (mounted) setState(() => _otpSent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyAndLogin() async {
    if (!Validators.isValidOtp(_otpController.text.trim())) {
      setState(() => _errorMessage = 'Enter the 6-digit code');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final token = await authRepo.verifyOtp(
        phone: _phone,
        otp: _otpController.text.trim(),
        purpose: OtpPurpose.login,
      );
      final result = await authRepo.loginOtp(_phone, token);
      await _onLoggedIn(result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changePhoneNumber() {
    setState(() {
      _otpSent = false;
      _otpController.clear();
      _errorMessage = null;
    });
  }

  Future<void> _onLoggedIn(AuthResult result) async {
    final localStorage = ref.read(localStorageProvider);
    await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
    await ref.read(sessionProvider.notifier).loadSession();
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    if (session is SessionAuthenticated) {
      Navigator.of(context).pushNamedAndRemoveUntil(session.homeRoute, (route) => false);
    }
  }

  /// Mirrors _onLoggedIn but saves into the caregiver's own (prefixed)
  /// LocalStorage keys and routes via the caregiver's own routeForStatus —
  /// this app and the ported caregiver flow are two independent sessions
  /// sharing one binary, not one shared session (see CLAUDE.md's JustHeal
  /// merge notes).
  Future<void> _onCaregiverLoggedIn(caregiver_auth.AuthResult result) async {
    final localStorage = ref.read(caregiver.localStorageProvider);
    await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
    await ref.read(caregiver_session.sessionProvider.notifier).loadSession();
    if (!mounted) return;
    final session = ref.read(caregiver_session.sessionProvider);
    if (session is caregiver_session_state.SessionAuthenticated) {
      Navigator.of(context).pushNamedAndRemoveUntil(caregiver_route.routeForStatus(session), (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpMode = ref.watch(otpModeProvider);

    return Scaffold(
      appBar: AppBar(
        actions: [
          // Entry point into the ported caregiver (NurseJobs) flow living
          // inside this same app/binary post-merge — see CLAUDE.md's
          // "Merged into one binary with NurseJobs". Goes straight to the
          // caregiver's own registration screen, not its splash/login,
          // matching this button's own label — an existing caregiver can
          // still reach their own login from there ("Already registered?"
          // equivalent link on that screen).
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/caregiver/register'),
            child: const Text('Caregivers Registration', style: TextStyle(color: AppColors.primary)),
          ),
          const WhatsAppHelpButton(),
        ],
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset(
                'packages/vitacare_ui/assets/branding/logo_icon.webp',
                width: 120,
                height: 120,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'JustHeal',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppTypography.jumbo, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (otpMode) ..._buildOtpFields() else ..._buildPinFields(),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: _loading ? null : (otpMode ? (_otpSent ? _verifyAndLogin : _sendOtp) : _submitPin),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(otpMode ? (_otpSent ? 'Verify & Login' : 'Send OTP') : 'Login'),
              ),
              if (otpMode && _otpSent) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _loading ? null : _sendOtp,
                  child: const Text('Resend OTP'),
                ),
                TextButton(
                  onPressed: _loading ? null : _changePhoneNumber,
                  child: const Text('Change phone number'),
                ),
              ],
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

  List<Widget> _buildPinFields() {
    return [
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
        onSubmitted: (_) => _submitPin(),
      ),
    ];
  }

  List<Widget> _buildOtpFields() {
    return [
      TextField(
        controller: _phoneController,
        enabled: !_otpSent,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          prefixText: '+91 ',
          labelText: 'Phone number',
          border: OutlineInputBorder(),
        ),
      ),
      if (_otpSent) ...[
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: '6-digit OTP',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _verifyAndLogin(),
        ),
      ],
    ];
  }
}
