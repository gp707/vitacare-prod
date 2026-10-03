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
import 'package:nursenow_app/caregiver/core/providers.dart' as caregiver;
import 'package:nursenow_app/caregiver/core/network/api_exception.dart' as caregiver_net;
import 'package:nursenow_app/caregiver/app/route_for_status.dart' as caregiver_route;
import 'package:nursenow_app/caregiver/features/auth/data/auth_result.dart' as caregiver_auth;
import 'package:nursenow_app/caregiver/features/auth/state/session_notifier.dart' as caregiver_session;
import 'package:nursenow_app/caregiver/features/auth/state/session_state.dart' as caregiver_session_state;

/// Colors from this screen's redesign spec that don't already match
/// vitacare_ui's shared AppColors palette (that palette is shared across
/// all 3 apps — these are specific to this one screen's refreshed look,
/// so they're kept local rather than added to the cross-app theme file).
/// AppColors.background (#F9FAFB) already matches the spec exactly and is
/// reused as-is below.
class _LoginPalette {
  _LoginPalette._();
  static const primaryBlue = Color(0xFF3662E3);
  static const helpRed = Color(0xFFCA3A31);
  static const textPrimary = Color(0xFF1B1B21);
  static const textSecondary = Color(0xFF555866);
  static const fieldBorder = Color(0xFF777680);
  static const rowBorder = Color(0xFFC4C6D0);
  static const divider = Color(0xFFD8D9E3);
  static const patientIconBg = Color(0xFFFBE7E1);
  static const patientIconFg = Color(0xFFA8412A);
  static const nurseIconBg = Color(0xFFDCEEEF);
  static const nurseIconFg = Color(0xFF2A666C);
  static const orgIconBg = Color(0xFFE3E8FD);
  static const orgIconFg = Color(0xFF2C4CC4);
}

/// One row in the "New here? Register as:" section — a full-width tappable
/// card with a coloured icon tile, title, one-line description, and a
/// trailing chevron. Exposed as a real button (Material+InkWell, ≥64px
/// tall so it clears the 44px minimum tap-target with room to spare) with
/// an explicit Semantics label, since the title/description are two
/// separate Text widgets a screen reader would otherwise announce as two
/// unrelated static lines rather than one tappable control.
class _RegisterOptionRow extends StatelessWidget {
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _RegisterOptionRow({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $description',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _LoginPalette.rowBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: AppTypography.subtitle,
                          fontWeight: FontWeight.w500,
                          color: _LoginPalette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(fontSize: 13, color: _LoginPalette.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: _LoginPalette.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
      // No AppBar — a dedicated toolbar strip left Help as the only thing
      // in an otherwise-empty full-width row. Instead it's positioned in
      // the corner of the same block as the logo/title (a Stack, not a
      // separate section), so it shares that space rather than pushing
      // everything else down a whole extra row's worth of height.
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Image.asset(
                    'packages/vitacare_ui/assets/branding/logo_lockup.webp',
                    width: 56,
                  ),
                  const Positioned(
                    top: 0,
                    right: 0,
                    child: WhatsAppHelpButton(
                      backgroundColor: _LoginPalette.helpRed,
                      margin: EdgeInsets.zero,
                      minimumSize: Size(0, 44),
                      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      iconSize: 16,
                      fontSize: AppTypography.body,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'JustHeal',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppTypography.jumbo,
                  fontWeight: FontWeight.bold,
                  color: _LoginPalette.primaryBlue,
                ),
              ),
              const Text(
                'By VitaCasaHealth.in',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppTypography.small, color: _LoginPalette.textSecondary),
              ),
              const SizedBox(height: 2),
              const Text(
                'Log in',
                style: TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.w500, color: _LoginPalette.textPrimary),
              ),
              const SizedBox(height: 2),
              const Text(
                'Already registered? Patients, nurses/caregivers and organisations all log in here.',
                style: TextStyle(fontSize: AppTypography.small, color: _LoginPalette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              if (otpMode) ..._buildOtpFields() else ..._buildPinFields(),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _loading ? null : (otpMode ? (_otpSent ? _verifyAndLogin : _sendOtp) : _submitPin),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _LoginPalette.primaryBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _LoginPalette.primaryBlue.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(otpMode ? (_otpSent ? 'Verify & Login' : 'Send OTP') : 'Log in'),
                ),
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
              const Divider(color: _LoginPalette.divider, height: 1),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'New here? Register as:',
                style: TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.w500, color: _LoginPalette.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Goes where "New here? Register" used to go — this screen's
              // RegistrationScreen defaults to the Individual/patient
              // account type.
              _RegisterOptionRow(
                icon: Icons.person,
                iconBackground: _LoginPalette.patientIconBg,
                iconColor: _LoginPalette.patientIconFg,
                title: 'Patient',
                description: 'I need care for me or my family',
                onTap: () => Navigator.of(context).pushNamed('/register'),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Goes where the old top-bar "Caregivers Registration" button
              // used to go — straight into the ported caregiver (NurseJobs)
              // flow's own registration screen (see CLAUDE.md's "Merged
              // into one binary with NurseJobs").
              _RegisterOptionRow(
                icon: Icons.favorite,
                iconBackground: _LoginPalette.nurseIconBg,
                iconColor: _LoginPalette.nurseIconFg,
                title: 'Nurses/Caregivers',
                description: 'I provide care and want to join',
                onTap: () => Navigator.of(context).pushNamed('/caregiver/register'),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Same RegistrationScreen as the Patient row, pre-selecting
              // its "Register as Organisation" checkbox — there is no
              // separate organisation registration flow (see
              // RegistrationScreen.startAsOrganisation).
              _RegisterOptionRow(
                icon: Icons.apartment,
                iconBackground: _LoginPalette.orgIconBg,
                iconColor: _LoginPalette.orgIconFg,
                title: 'Organisation',
                description: 'We arrange care for our patients',
                onTap: () => Navigator.of(context).pushNamed('/register', arguments: true),
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
          isDense: true,
          prefixText: '+91 ',
          labelText: 'Phone number',
          border: OutlineInputBorder(borderSide: BorderSide(color: _LoginPalette.fieldBorder)),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        decoration: const InputDecoration(
          isDense: true,
          labelText: '4-digit code',
          border: OutlineInputBorder(borderSide: BorderSide(color: _LoginPalette.fieldBorder)),
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
          isDense: true,
          prefixText: '+91 ',
          labelText: 'Phone number',
          border: OutlineInputBorder(borderSide: BorderSide(color: _LoginPalette.fieldBorder)),
        ),
      ),
      if (_otpSent) ...[
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            isDense: true,
            labelText: '6-digit OTP',
            border: OutlineInputBorder(borderSide: BorderSide(color: _LoginPalette.fieldBorder)),
          ),
          onSubmitted: (_) => _verifyAndLogin(),
        ),
      ],
    ];
  }
}
