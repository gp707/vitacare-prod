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
/// posting is currently blocked, and every self-editable field shown
/// inline: a pencil icon next to the current value, tapping it turns that
/// one field into an editable input in place with its own Save/Cancel
/// icons, rather than a whole always-visible form with a single shared
/// Save button. Phone is deliberately NOT editable here at all (see the
/// WhatsApp pointer text below) — self-service phone change was removed
/// from the product entirely.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Individual-only — unlike a caregiver's full_name (locked from
  /// self-edit — only admins can change it), a patient/family account can
  /// freely update their own name. Not offered for Organisation (the
  /// "contact person" name is its own inline field below, saved via
  /// _saveOrgField instead).
  Future<String?> _saveName(String value) async {
    final error = _nameValidationError(value);
    if (error != null) return error;
    try {
      await ref.read(individualRepositoryProvider).updateName(value);
      await ref.read(sessionProvider.notifier).loadSession();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  String? _nameValidationError(String value) {
    if (value.length > Validation.nameMaxLength) {
      return 'Name must be ${Validation.nameMaxLength} characters or fewer';
    }
    if (!Validators.isValidName(value)) {
      return 'Enter a valid name (letters and spaces only)';
    }
    return null;
  }

  /// Organisation-only — each org-owned field saves independently (the
  /// repository/backend both accept a partial update), unlike the old
  /// single "Save Organisation Details" button that always sent every
  /// field together.
  Future<String?> _saveOrgField({
    String? fullName,
    String? organisationName,
    String? organisationType,
    String? city,
    String? area,
  }) async {
    try {
      await ref.read(organisationRepositoryProvider).updateProfile(
            fullName: fullName,
            organisationName: organisationName,
            organisationType: organisationType,
            city: city,
            area: area,
          );
      await ref.read(sessionProvider.notifier).loadSession();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> _saveCode(String code, bool isOrganisation) async {
    try {
      if (isOrganisation) {
        await ref.read(organisationRepositoryProvider).updateCode(code);
      } else {
        await ref.read(individualRepositoryProvider).updateCode(code);
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
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
                  const SizedBox(height: 2),
                  const Text(
                    "To change the mobile number linked to your account, tap the Help button above to chat "
                    "with us on WhatsApp and let us know.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
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
                    _InlineTextField(
                      icon: Icons.badge,
                      label: 'Full Name',
                      value: authenticated.fullName,
                      maxLength: Validation.nameMaxLength,
                      validate: _nameValidationError,
                      onSave: _saveName,
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
                    _InlineTextField(
                      icon: Icons.person,
                      label: 'Contact person name',
                      value: authenticated.fullName,
                      maxLength: Validation.nameMaxLength,
                      validate: _nameValidationError,
                      onSave: (v) => _saveOrgField(fullName: v),
                    ),
                    _InlineTextField(
                      icon: Icons.apartment,
                      label: 'Organisation name',
                      value: authenticated.organisationName ?? '',
                      validate: (v) => v.trim().isEmpty ? 'Organisation name is required' : null,
                      onSave: (v) => _saveOrgField(organisationName: v),
                    ),
                    _InlineDropdownField(
                      icon: Icons.category,
                      label: 'Type of organisation',
                      value: authenticated.organisationType,
                      displayValue:
                          OrganisationType.displayNames[authenticated.organisationType] ?? authenticated.organisationType ?? '',
                      items: OrganisationType.all
                          .map((t) => DropdownMenuItem(value: t, child: Text(OrganisationType.displayNames[t] ?? t)))
                          .toList(),
                      onSave: (v) => _saveOrgField(organisationType: v),
                    ),
                    _InlineDropdownField(
                      icon: Icons.location_city,
                      label: 'City',
                      value: authenticated.city,
                      displayValue: City.displayNames[authenticated.city] ?? authenticated.city ?? '',
                      items: [
                        ...City.all.map((c) => DropdownMenuItem(value: c, child: Text(City.displayNames[c] ?? c))),
                        const DropdownMenuItem(value: 'others', child: Text('Others')),
                      ],
                      onSave: (v) => _saveOrgField(city: v),
                    ),
                    _InlineTextField(
                      icon: Icons.map,
                      label: 'Area (Optional)',
                      value: authenticated.area ?? '',
                      // Matches the previous form's own semantics: clearing
                      // this field back to empty is treated as "nothing to
                      // update" (sent as null, so the existing area stays
                      // put) rather than an unset request — there's no
                      // backend support for clearing area once set.
                      onSave: (v) => _saveOrgField(area: v.trim().isEmpty ? null : v.trim()),
                    ),
                  ],
                  const Divider(height: AppSpacing.xxl),
                  _InlinePinField(onSave: (code) => _saveCode(code, authenticated.isOrganisation)),
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

/// Shared "pencil icon → inline edit in place" chrome (the label, the
/// pencil/check/close icon row, and the error line) reused by every
/// concrete inline field type below — each subclass only needs to supply
/// what its display/edit widgets look like.
abstract class _InlineFieldRow<T> extends StatefulWidget {
  final IconData icon;
  final String label;

  const _InlineFieldRow({required this.icon, required this.label});
}

abstract class _InlineFieldRowState<T, W extends _InlineFieldRow<T>> extends State<W> {
  bool editing = false;
  bool saving = false;
  String? error;

  /// The current (non-editing) value to show, and to reset to on cancel.
  T get committedValue;

  /// Called when entering edit mode — resets any local editing state
  /// (e.g. a controller's text) back to [committedValue].
  void resetEditingState();

  /// Builds the field's own input widget while editing (TextField,
  /// DropdownButtonFormField, etc).
  Widget buildEditor(BuildContext context);

  /// Builds the plain display Text/Row shown while not editing.
  Widget buildDisplay(BuildContext context);

  /// Returns an error message to show instead of saving, or null to
  /// proceed — checked before calling the async save callback.
  String? validateBeforeSave();

  /// Performs the actual save; returns an error message on failure, or
  /// null on success.
  Future<String?> save();

  void startEditing() {
    setState(() {
      resetEditingState();
      editing = true;
      error = null;
    });
  }

  void cancel() {
    setState(() {
      editing = false;
      error = null;
      resetEditingState();
    });
  }

  Future<void> handleSave() async {
    final validationError = validateBeforeSave();
    if (validationError != null) {
      setState(() => error = validationError);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final saveError = await save();
    if (!mounted) return;
    setState(() {
      saving = false;
      if (saveError != null) {
        error = saveError;
      } else {
        editing = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: editing ? buildEditor(context) : buildDisplay(context)),
              if (editing) ...[
                if (saving)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: SizedBox(height: 18, width: 18, child: VitaLoadingIndicator(size: 18)),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.check, color: AppColors.success),
                    tooltip: 'Save',
                    onPressed: handleSave,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.error),
                    tooltip: 'Cancel',
                    onPressed: cancel,
                  ),
                ],
              ] else
                IconButton(
                  icon: const Icon(Icons.edit, size: 18, color: AppColors.primaryDark),
                  tooltip: 'Edit ${widget.label}',
                  onPressed: startEditing,
                ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(error!, style: const TextStyle(color: AppColors.error, fontSize: AppTypography.small)),
            ),
        ],
      ),
    );
  }
}

// Stacked (label above, value below) rather than side-by-side — some of
// these labels ("Type of organisation") are long enough that a horizontal
// layout overflows on a narrow phone once the pencil/check/close icons
// also claim their own space in the same row.
Widget _displayRow(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.small)),
        Text(
          value,
          style: const TextStyle(color: AppColors.textSecondary),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

class _InlineTextField extends _InlineFieldRow<String> {
  final String value;
  final int? maxLength;
  final String? Function(String value)? validate;
  final Future<String?> Function(String value) onSave;

  const _InlineTextField({
    required super.icon,
    required super.label,
    required this.value,
    required this.onSave,
    this.maxLength,
    this.validate,
  });

  @override
  State<_InlineTextField> createState() => _InlineTextFieldState();
}

class _InlineTextFieldState extends _InlineFieldRowState<String, _InlineTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  String get committedValue => widget.value;

  @override
  void didUpdateWidget(covariant _InlineTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!editing && widget.value != oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void resetEditingState() => _controller.text = committedValue;

  @override
  String? validateBeforeSave() => widget.validate?.call(_controller.text.trim());

  @override
  Future<String?> save() => widget.onSave(_controller.text.trim());

  @override
  Widget buildEditor(BuildContext context) => TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: InputDecoration(labelText: widget.label, isDense: true),
      );

  @override
  Widget buildDisplay(BuildContext context) => _displayRow(widget.label, widget.value.isEmpty ? '—' : widget.value);
}

class _InlineDropdownField extends _InlineFieldRow<String?> {
  final String? value;
  final String displayValue;
  final List<DropdownMenuItem<String>> items;
  final Future<String?> Function(String value) onSave;

  const _InlineDropdownField({
    required super.icon,
    required super.label,
    required this.value,
    required this.displayValue,
    required this.items,
    required this.onSave,
  });

  @override
  State<_InlineDropdownField> createState() => _InlineDropdownFieldState();
}

class _InlineDropdownFieldState extends _InlineFieldRowState<String?, _InlineDropdownField> {
  late String? _pending = widget.value;

  @override
  String? get committedValue => widget.value;

  @override
  void resetEditingState() => _pending = committedValue;

  @override
  String? validateBeforeSave() => _pending == null ? 'Select a value' : null;

  @override
  Future<String?> save() => widget.onSave(_pending!);

  @override
  Widget buildEditor(BuildContext context) => DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _pending,
        decoration: InputDecoration(labelText: widget.label, isDense: true),
        items: widget.items,
        onChanged: (v) => setState(() => _pending = v),
      );

  @override
  Widget buildDisplay(BuildContext context) => _displayRow(widget.label, widget.displayValue);
}

class _InlinePinField extends StatefulWidget {
  final Future<String?> Function(String code) onSave;

  const _InlinePinField({required this.onSave});

  @override
  State<_InlinePinField> createState() => _InlinePinFieldState();
}

class _InlinePinFieldState extends State<_InlinePinField> {
  bool _editing = false;
  bool _saving = false;
  String? _error;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _controller.clear();
      _editing = true;
      _error = null;
    });
  }

  void _cancel() {
    setState(() {
      _editing = false;
      _error = null;
      _controller.clear();
    });
  }

  Future<void> _save() async {
    final code = _controller.text.trim();
    if (!Validators.isValidCode(code)) {
      setState(() => _error = 'PIN must be exactly 4 digits');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(code);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error != null) {
        _error = error;
      } else {
        _editing = false;
        _controller.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _editing
                    ? TextField(
                        controller: _controller,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: Validation.codeLength,
                        decoration: const InputDecoration(labelText: 'New 4-digit PIN', isDense: true),
                      )
                    : const Row(
                        children: [
                          Text('Login PIN', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(width: AppSpacing.sm),
                          Text('••••', style: TextStyle(color: AppColors.textSecondary, letterSpacing: 2)),
                        ],
                      ),
              ),
              if (_editing) ...[
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: SizedBox(height: 18, width: 18, child: VitaLoadingIndicator(size: 18)),
                  )
                else ...[
                  IconButton(icon: const Icon(Icons.check, color: AppColors.success), tooltip: 'Save', onPressed: _save),
                  IconButton(icon: const Icon(Icons.close, color: AppColors.error), tooltip: 'Cancel', onPressed: _cancel),
                ],
              ] else
                IconButton(
                  icon: const Icon(Icons.edit, size: 18, color: AppColors.primaryDark),
                  tooltip: 'Edit Login PIN',
                  onPressed: _startEditing,
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: AppTypography.small)),
            ),
        ],
      ),
    );
  }
}
