import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/messages_bell.dart';
import '../../../app/nursenow_bottom_nav.dart';
import '../../../app/scope_of_work_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../caregiver_profile/screens/caregiver_profile_view_screen.dart';
import '../data/individual_repository.dart';
import '../widgets/area_char_limit_note.dart';
import '../widgets/duty_requirements_button.dart';
import '../widgets/section_box.dart';

// A UI-only sentinel — never sent to the backend as-is. Mutually exclusive
// with every real language: picking a real language drops this, picking
// this drops every real language. Translated to an empty `languages: []`
// array at submission time, which the backend treats as "No Preference"
// (see UpdateIndividualRequirementDto).
const _noPreferenceLanguage = 'no_preference';

// A UI-only sentinel — never sent to the backend as-is. Mutually exclusive
// with every real condition: picking a real condition drops this, picking
// this drops every real condition. Translated to
// `has_medical_condition: false` (and no `medical_conditions`) at
// submission time — the mandatory-but-can-be-none equivalent of
// _noPreferenceLanguage above.
const _noneMedicalCondition = 'none';
const _noneMedicalConditionLabel = 'None';

class _MandatoryField {
  final GlobalKey key;
  final bool isValid;
  final FocusNode? focusNode;

  const _MandatoryField(this.key, this.isValid, {this.focusNode});
}

/// Full requirement history for this account — every past posting stays
/// visible (pending review / live / rejected / closed), not just the
/// current one, so a patient/family can always see who was accepted on a
/// past requirement even after it's closed. There is no "post a new
/// requirement" action anywhere in this screen any more — posting only
/// ever happens once, as part of registration itself (RegistrationScreen),
/// so every individual account has exactly one requirement in its history.
class JobsPostedScreen extends ConsumerStatefulWidget {
  const JobsPostedScreen({super.key});

  @override
  ConsumerState<JobsPostedScreen> createState() => _JobsPostedScreenState();
}

class _JobsPostedScreenState extends ConsumerState<JobsPostedScreen> {
  bool _loading = true;
  String? _error;
  List<JobModel> _requirements = [];
  Map<String, List<JobApplicationModel>> _applicationsByJobId = {};
  final Set<String> _decidingApplicationId = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(individualRepositoryProvider);
      final requirements = await repo.listMyRequirements();
      // pending_review can never have applications yet — skip the request
      // for those, fetch for every other requirement (active AND closed,
      // so a past requirement's accepted/declined applicants stay visible
      // after it closes, not just while it's live).
      final withApplications = requirements
          .where((r) => r.status != JobStatus.pendingReview)
          .toList();
      final applicationLists = await Future.wait(
          withApplications.map((r) => repo.listApplications(r.id)));
      if (!mounted) return;
      setState(() {
        _requirements = requirements;
        _applicationsByJobId = {
          for (var i = 0; i < withApplications.length; i++)
            withApplications[i].id: applicationLists[i],
        };
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(String jobId, String applicationId) async {
    setState(() => _decidingApplicationId.add(applicationId));
    try {
      await ref.read(individualRepositoryProvider).decideApplication(
          jobId, applicationId, JobApplicationStatus.accepted);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showVitaErrorBanner(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _decidingApplicationId.remove(applicationId));
    }
  }

  /// A reason is mandatory (JOB_012 is the server-side backstop) — the
  /// dialog's Confirm button stays disabled until something is typed, so
  /// there's no way to submit a reject without one.
  Future<void> _rejectWithReason(String jobId, String applicationId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Decline this candidate'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 1000,
            maxLines: 3,
            onChanged: (_) => setDialogState(() {}),
            decoration: const InputDecoration(
                labelText: 'Reason (required, shown to no one but you)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () =>
                      Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty) return;

    setState(() => _decidingApplicationId.add(applicationId));
    try {
      await ref.read(individualRepositoryProvider).decideApplication(
          jobId, applicationId, JobApplicationStatus.rejected,
          reason: reason);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showVitaErrorBanner(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _decidingApplicationId.remove(applicationId));
    }
  }

  /// The single candidate currently under review, per the forced
  /// one-at-a-time flow — see _ApplicantsSection.
  void _viewProfile(String jobId, String applicationId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaregiverProfileViewScreen(
          fetchProfile: () => ref
              .read(individualRepositoryProvider)
              .getApplicantProfile(jobId, applicationId),
        ),
      ),
    );
  }

  /// Allowed at any point in the requirement's lifecycle — regardless of
  /// applications, and regardless of whether it's already closed by an
  /// acceptance (see the backend's JOB_015, which only blocks cancelling
  /// something already rejected/cancelled). Confirmed first since it's
  /// irreversible and, when candidates are involved, notifies them by
  /// rejecting their application.
  Future<void> _cancelRequirement(JobModel requirement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this requirement?'),
        content: const Text(
          'Any candidates who applied or were accepted will have their application declined as '
          "cancelled, and you won't be able to see who applied afterward. You can make this "
          'requirement active again later, but today\'s applicant list will not come back.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No, keep it')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, cancel it',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(individualRepositoryProvider)
          .cancelRequirement(requirement.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showVitaErrorBanner(context, e.message);
      }
    }
  }

  /// Brings a cancelled requirement back to active — no confirmation
  /// dialog needed (unlike cancel, this isn't destructive), matching
  /// Organisation's own "Unhide and Make it Live" action.
  Future<void> _reactivateRequirement(JobModel requirement) async {
    try {
      await ref
          .read(individualRepositoryProvider)
          .reactivateRequirement(requirement.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showVitaErrorBanner(context, e.message);
      }
    }
  }

  /// An individual account only ever has one requirement in its whole
  /// history (see "Registration IS posting" in CLAUDE.md), so there is no
  /// reason to hide anything behind a toggle — every requirement found is
  /// always shown directly.
  Widget _buildCard(JobModel requirement) {
    return _RequirementCard(
      requirement: requirement,
      applications: _applicationsByJobId[requirement.id] ?? const [],
      decidingApplicationId: _decidingApplicationId,
      onAccept: (applicationId) => _accept(requirement.id, applicationId),
      onReject: (applicationId) =>
          _rejectWithReason(requirement.id, applicationId),
      onViewProfile: (applicationId) =>
          _viewProfile(requirement.id, applicationId),
      onCancel: () => _cancelRequirement(requirement),
      onReactivate: () => _reactivateRequirement(requirement),
      onSaved: _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const VitaAppBarTitle('Requirement Posted'),
        actions: individualAppBarActions(showBell: true),
      ),
      backgroundColor: AppColors.background,
      bottomNavigationBar: const NurseNowBottomNav(currentIndex: 1),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: VitaLoadingIndicator())
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (_error != null)
                      Text(_error!,
                          style: const TextStyle(color: AppColors.error)),
                    if (_requirements.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Text(
                          "You don't have any requirements posted yet.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      for (final requirement in _requirements) ...[
                        _buildCard(requirement),
                        const SizedBox(height: AppSpacing.md),
                      ],
                  ],
                ),
        ),
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

// Seconds are included (not just hours:minutes) so two actions taken within
// the same minute — e.g. a caregiver rejecting right after another applied —
// still display in a visibly distinguishable, correctly ordered sequence.
// The underlying DateTime already carries full precision from the backend
// (Postgres timestamptz); this only affects what's shown, not how anything
// is sorted (sorting already compares full DateTime/ISO values).
String _formatDateTime(DateTime date) =>
    '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:'
    '${date.second.toString().padLeft(2, '0')}';

class _RequirementCard extends ConsumerStatefulWidget {
  final JobModel requirement;
  final List<JobApplicationModel> applications;
  final Set<String> decidingApplicationId;
  final void Function(String applicationId) onAccept;
  final void Function(String applicationId) onReject;
  final void Function(String applicationId) onViewProfile;
  final VoidCallback onCancel;
  final VoidCallback onReactivate;
  final VoidCallback onSaved;

  const _RequirementCard({
    required this.requirement,
    required this.applications,
    required this.decidingApplicationId,
    required this.onAccept,
    required this.onReject,
    required this.onViewProfile,
    required this.onCancel,
    required this.onReactivate,
    required this.onSaved,
  });

  @override
  ConsumerState<_RequirementCard> createState() => _RequirementCardState();
}

class _RequirementCardState extends ConsumerState<_RequirementCard> {
  // --- Inline edit state, pre-filled from widget.requirement in initState
  // and submitted via editRequirement on Save — replaces the old
  // standalone EditRequirementScreen entirely; every field is always shown
  // and always editable right here on the card (disabled, not hidden,
  // while locked — see _hasActiveApplication). Field set/order/validation
  // mirrors the old PostRequirementScreen/EditRequirementScreen exactly. ---
  final _patientNameController = TextEditingController();
  final _ageController = TextEditingController();
  String? _gender;
  final _weightController = TextEditingController();
  String? _feedingType;
  final List<String> _medicalConditions = [_noneMedicalCondition];
  final _medicalConditionOtherController = TextEditingController();
  final List<String> _toiletAssistance = [];
  final _toiletAssistanceOtherController = TextEditingController();
  String? _city;
  final _areaController = TextEditingController();
  String? _dutyType;
  DateTime? _startDate;
  String? _careDuration;
  final List<String> _languages = [_noPreferenceLanguage];
  String? _preferredGender;
  String? _preferredReligion;
  final _salaryController = TextEditingController();
  String? _lastAutoSuggestedSalary;
  List<RateCardModel> _rateCards = const [];

  bool _saving = false;
  String? _error;

  final _patientNameFocusNode = FocusNode();
  final _ageFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();
  final _areaFocusNode = FocusNode();

  final _patientNameKey = GlobalKey();
  final _ageKey = GlobalKey();
  final _genderKey = GlobalKey();
  final _weightKey = GlobalKey();
  final _cityKey = GlobalKey();
  final _areaKey = GlobalKey();
  final _dutyTypeKey = GlobalKey();
  final _startDateKey = GlobalKey();
  final _careDurationKey = GlobalKey();
  final _toiletAssistanceKey = GlobalKey();
  final _feedingTypeKey = GlobalKey();
  final _salaryKey = GlobalKey();

  bool _showValidationErrors = false;

  // Collapsed by default — the card already shows status/applicants/salary
  // up front; these two sections are opened on demand rather than always
  // taking up the full height of every field at once. A mandatory-field
  // validation failure force-expands whichever section the invalid field
  // lives in before focusing/scrolling to it (see _handleSavePressed) —
  // otherwise that field wouldn't be mounted for Scrollable.ensureVisible
  // to find.
  bool _patientDetailsExpanded = false;
  bool _carePreferencesExpanded = false;

  bool _isPatientDetailsField(GlobalKey key) =>
      key == _patientNameKey ||
      key == _ageKey ||
      key == _genderKey ||
      key == _weightKey ||
      key == _cityKey ||
      key == _areaKey;

  @override
  void initState() {
    super.initState();
    _populateFromRequirement();
    _loadRateCards();
  }

  /// Fills every field from [widget.requirement] — called once from
  /// initState. Per-field reverts (the cross button next to whichever
  /// field was touched — see _revertAge/_revertGender/etc.) only reset
  /// that one field, not the whole form; there's no "discard everything"
  /// action any more.
  void _populateFromRequirement() {
    final job = widget.requirement;
    final cr = job.careReceiver;
    _medicalConditions
      ..clear()
      ..add(_noneMedicalCondition);
    _toiletAssistance.clear();
    _languages
      ..clear()
      ..add(_noPreferenceLanguage);
    if (cr != null) {
      _patientNameController.text = cr.patientName ?? '';
      _ageController.text = cr.age.toString();
      _gender = cr.gender;
      _weightController.text = cr.weightKg.toString();
      _feedingType = cr.feedingType;
      if (cr.hasMedicalCondition && cr.medicalConditions.isNotEmpty) {
        _medicalConditions
          ..clear()
          ..addAll(cr.medicalConditions);
      }
      _medicalConditionOtherController.text = cr.medicalConditionOther ?? '';
      _toiletAssistance.addAll(cr.toiletAssistance);
      _toiletAssistanceOtherController.text = cr.toiletAssistanceOther ?? '';
    } else {
      _patientNameController.clear();
      _ageController.clear();
      _gender = null;
      _weightController.clear();
      _feedingType = null;
      _medicalConditionOtherController.clear();
      _toiletAssistanceOtherController.clear();
    }
    _city = job.city;
    _areaController.text = job.area ?? '';
    _dutyType = job.dutyType;
    _startDate = job.startDate == null ? null : DateTime.tryParse(job.startDate!);
    _careDuration = job.careDuration;
    if (job.languages.isNotEmpty) {
      _languages
        ..clear()
        ..addAll(job.languages);
    }
    _preferredGender = job.preferredGender;
    _preferredReligion = job.preferredReligion;
    _salaryController.text = job.salaryAmount ?? '';
  }

  // --- Per-field dirty checks + reverts, each field compared only against
  // its own original value on widget.requirement — these back the inline
  // tick/cross controls shown right next to whichever field was actually
  // touched (see _fieldControls), rather than one consolidated Save/Discard
  // pair far below a long form. The tick on every field triggers the same
  // _handleSavePressed (there's no partial-field save endpoint — Save
  // always submits the form's full current state); the cross only reverts
  // that one field. ---
  bool get _isPatientNameDirty {
    final cr = widget.requirement.careReceiver;
    return cr != null && _patientNameController.text != (cr.patientName ?? '');
  }

  void _revertPatientName() => setState(() {
        final cr = widget.requirement.careReceiver;
        if (cr != null) _patientNameController.text = cr.patientName ?? '';
      });

  bool get _isAgeDirty {
    final cr = widget.requirement.careReceiver;
    return cr != null && _ageController.text != cr.age.toString();
  }

  void _revertAge() => setState(() {
        final cr = widget.requirement.careReceiver;
        if (cr != null) _ageController.text = cr.age.toString();
      });

  bool get _isGenderDirty {
    final cr = widget.requirement.careReceiver;
    return cr != null && _gender != cr.gender;
  }

  void _revertGender() => setState(() => _gender = widget.requirement.careReceiver?.gender);

  bool get _isWeightDirty {
    final cr = widget.requirement.careReceiver;
    return cr != null && _weightController.text != cr.weightKg.toString();
  }

  void _revertWeight() => setState(() {
        final cr = widget.requirement.careReceiver;
        if (cr != null) _weightController.text = cr.weightKg.toString();
      });

  bool get _isCityDirty => _city != widget.requirement.city;

  void _revertCity() => setState(() => _city = widget.requirement.city);

  bool get _isAreaDirty => _areaController.text != (widget.requirement.area ?? '');

  void _revertArea() => setState(() => _areaController.text = widget.requirement.area ?? '');

  bool get _isMedicalConditionDirty {
    final cr = widget.requirement.careReceiver;
    if (cr == null) return false;
    final original = cr.hasMedicalCondition && cr.medicalConditions.isNotEmpty
        ? cr.medicalConditions.toSet()
        : {_noneMedicalCondition};
    return !setEquals(_medicalConditions.toSet(), original) ||
        _medicalConditionOtherController.text != (cr.medicalConditionOther ?? '');
  }

  void _revertMedicalCondition() => setState(() {
        final cr = widget.requirement.careReceiver;
        _medicalConditions.clear();
        if (cr != null && cr.hasMedicalCondition && cr.medicalConditions.isNotEmpty) {
          _medicalConditions.addAll(cr.medicalConditions);
        } else {
          _medicalConditions.add(_noneMedicalCondition);
        }
        _medicalConditionOtherController.text = cr?.medicalConditionOther ?? '';
        _refreshSuggestedSalary();
      });

  bool get _isDutyTypeDirty => _dutyType != widget.requirement.dutyType;

  void _revertDutyType() => setState(() => _dutyType = widget.requirement.dutyType);

  bool get _isStartDateDirty {
    final original = widget.requirement.startDate == null ? null : DateTime.tryParse(widget.requirement.startDate!);
    return _startDate != original;
  }

  void _revertStartDate() => setState(() {
        _startDate = widget.requirement.startDate == null ? null : DateTime.tryParse(widget.requirement.startDate!);
      });

  bool get _isCareDurationDirty => _careDuration != widget.requirement.careDuration;

  void _revertCareDuration() => setState(() {
        _careDuration = widget.requirement.careDuration;
        _refreshSuggestedSalary();
      });

  bool get _isToiletAssistanceDirty {
    final cr = widget.requirement.careReceiver;
    if (cr == null) return false;
    return !setEquals(_toiletAssistance.toSet(), cr.toiletAssistance.toSet()) ||
        _toiletAssistanceOtherController.text != (cr.toiletAssistanceOther ?? '');
  }

  void _revertToiletAssistance() => setState(() {
        final cr = widget.requirement.careReceiver;
        _toiletAssistance.clear();
        if (cr != null) _toiletAssistance.addAll(cr.toiletAssistance);
        _toiletAssistanceOtherController.text = cr?.toiletAssistanceOther ?? '';
        _refreshSuggestedSalary();
      });

  bool get _isFeedingTypeDirty {
    final cr = widget.requirement.careReceiver;
    return cr != null && _feedingType != cr.feedingType;
  }

  void _revertFeedingType() => setState(() {
        _feedingType = widget.requirement.careReceiver?.feedingType;
        _refreshSuggestedSalary();
      });

  bool get _isPreferredGenderDirty => _preferredGender != widget.requirement.preferredGender;

  void _revertPreferredGender() => setState(() => _preferredGender = widget.requirement.preferredGender);

  /// Compact tick/cross pair shown right next to a field once it differs
  /// from what's actually saved — null (nothing rendered) otherwise. Tick
  /// always runs the same full-form [_handleSavePressed]; cross reverts
  /// only this one field via [onRevert].
  Widget? _fieldControls(String fieldName, bool dirty, VoidCallback onRevert) {
    if (!dirty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('$fieldName-save'),
          icon: const Icon(Icons.check_circle, color: AppColors.success),
          tooltip: 'Save changes',
          visualDensity: VisualDensity.compact,
          onPressed: _saving ? null : _handleSavePressed,
        ),
        IconButton(
          key: Key('$fieldName-discard'),
          icon: const Icon(Icons.cancel, color: AppColors.error),
          tooltip: 'Discard this change',
          visualDensity: VisualDensity.compact,
          onPressed: _saving ? null : onRevert,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _medicalConditionOtherController.dispose();
    _toiletAssistanceOtherController.dispose();
    _areaController.dispose();
    _salaryController.dispose();
    _patientNameFocusNode.dispose();
    _ageFocusNode.dispose();
    _weightFocusNode.dispose();
    _areaFocusNode.dispose();
    super.dispose();
  }

  /// Fire-and-forget, called once from initState — fetches the Rate Card,
  /// then applies the first suggestion it resolves to. Fails open: a
  /// network error just leaves the existing salary_amount untouched. After
  /// this, further field changes go through _refreshSuggestedSalary
  /// instead, which never overwrites something the patient has typed.
  Future<void> _loadRateCards() async {
    try {
      final rateCards = await ref.read(rateCardRepositoryProvider).get();
      if (!mounted) return;
      setState(() => _rateCards = rateCards);
      final careReceiver = _careReceiverForTierDerivation;
      final careDuration = _careDuration;
      if (careReceiver == null || careDuration == null) return;
      final tier = deriveCareTier(careReceiver);
      final frequency = frequencyForCareDuration(careDuration);
      final suggestion = suggestedRate(_rateCards, tier, frequency);
      if (suggestion != null) {
        setState(() {
          _salaryController.text = suggestion;
          _lastAutoSuggestedSalary = suggestion;
        });
      }
    } catch (_) {
      // Fail open — see doc comment above.
    }
  }

  void _refreshSuggestedSalary() {
    final careReceiver = _careReceiverForTierDerivation;
    final careDuration = _careDuration;
    if (careReceiver == null || careDuration == null) return;
    final tier = deriveCareTier(careReceiver);
    final frequency = frequencyForCareDuration(careDuration);
    final suggestion = suggestedRate(_rateCards, tier, frequency);
    if (suggestion == null) return;
    if (_salaryController.text.isEmpty || _salaryController.text == _lastAutoSuggestedSalary) {
      _salaryController.text = suggestion;
      _lastAutoSuggestedSalary = suggestion;
    }
  }

  /// Rebuilds a CareReceiverModel from whatever's currently live-edited on
  /// this card (toilet assistance, feeding type, medical condition), mixed
  /// with the field this card never edits (vitals monitoring) preserved
  /// from the original — so the derived tier always reflects the latest
  /// in-progress edits, not a stale snapshot from when first posted.
  CareReceiverModel? get _careReceiverForTierDerivation {
    final cr = widget.requirement.careReceiver;
    if (cr == null) return null;
    return CareReceiverModel(
      id: cr.id,
      age: cr.age,
      gender: cr.gender,
      weightKg: cr.weightKg,
      feedingType: _feedingType ?? FeedingType.oralFeeding,
      hasMedicalCondition: !_medicalConditions.contains(_noneMedicalCondition),
      medicalConditions: _medicalConditions.contains(_noneMedicalCondition) ? [] : _medicalConditions,
      toiletAssistance: _toiletAssistance,
      requiresVitalMonitoring: cr.requiresVitalMonitoring,
      vitalMonitoringTypes: cr.vitalMonitoringTypes,
    );
  }

  String? get _derivedFrequencyOfCare =>
      _careDuration == null ? null : frequencyForCareDuration(_careDuration!);

  int? get _age => int.tryParse(_ageController.text.trim());
  int? get _weightKg => int.tryParse(_weightController.text.trim());

  bool get _isPatientNameValid => Validators.isValidName(_patientNameController.text.trim());
  bool get _isAgeValid => _age != null && _age! >= 1 && _age! <= 120;
  bool get _isGenderValid => _gender != null;
  bool get _isWeightValid => _weightKg != null && _weightKg! >= 1 && _weightKg! <= 300;
  bool get _isCityValid => _city != null;
  bool get _isAreaValid => _areaController.text.trim().isNotEmpty;
  bool get _isDutyTypeValid => _dutyType != null;
  bool get _isStartDateValid => _startDate != null;
  bool get _isCareDurationValid => _careDuration != null;
  bool get _isToiletAssistanceValid => _toiletAssistance.isNotEmpty;
  bool get _isFeedingTypeValid => _feedingType != null;
  bool get _isSalaryValid => _salaryController.text.trim().isNotEmpty;

  bool get _showGenderMismatchWarning => _gender == Gender.male && _preferredGender == Gender.female;
  bool get _showShortTermDurationWarning =>
      _careDuration == CareDuration.fewDays || _careDuration == CareDuration.fewWeeks;

  bool get _canSave =>
      !_saving &&
      _isPatientNameValid &&
      _isAgeValid &&
      _isGenderValid &&
      _isWeightValid &&
      _isCityValid &&
      _isAreaValid &&
      _isDutyTypeValid &&
      _isStartDateValid &&
      _isCareDurationValid &&
      _isToiletAssistanceValid &&
      _isFeedingTypeValid &&
      _isSalaryValid;

  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_patientNameKey, _isPatientNameValid, focusNode: _patientNameFocusNode),
        _MandatoryField(_ageKey, _isAgeValid, focusNode: _ageFocusNode),
        _MandatoryField(_genderKey, _isGenderValid),
        _MandatoryField(_weightKey, _isWeightValid, focusNode: _weightFocusNode),
        _MandatoryField(_cityKey, _isCityValid),
        _MandatoryField(_areaKey, _isAreaValid, focusNode: _areaFocusNode),
        _MandatoryField(_dutyTypeKey, _isDutyTypeValid),
        _MandatoryField(_startDateKey, _isStartDateValid),
        _MandatoryField(_careDurationKey, _isCareDurationValid),
        _MandatoryField(_toiletAssistanceKey, _isToiletAssistanceValid),
        _MandatoryField(_feedingTypeKey, _isFeedingTypeValid),
        _MandatoryField(_salaryKey, _isSalaryValid),
      ];

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  void _applyMedicalConditionSelection(List<String> next) {
    final added = next.where((c) => !_medicalConditions.contains(c));
    final removed = _medicalConditions.where((c) => !next.contains(c));
    if (added.contains(_noneMedicalCondition)) {
      _medicalConditions
        ..clear()
        ..add(_noneMedicalCondition);
    } else if (added.isNotEmpty) {
      _medicalConditions
        ..clear()
        ..addAll(next.where((c) => c != _noneMedicalCondition));
    } else if (removed.isNotEmpty) {
      final remaining = next.where((c) => c != _noneMedicalCondition).toList();
      _medicalConditions
        ..clear()
        ..addAll(remaining.isEmpty ? [_noneMedicalCondition] : remaining);
    }
  }

  Future<void> _handleSavePressed() async {
    if (_saving) return;
    if (!_canSave) {
      setState(() => _showValidationErrors = true);
      _MandatoryField? firstInvalid;
      for (final field in _mandatoryFieldsInOrder) {
        if (!field.isValid) {
          firstInvalid = field;
          break;
        }
      }
      if (firstInvalid != null) {
        final target = firstInvalid;
        // Force open whichever section the invalid field lives in — a
        // collapsed section's fields aren't mounted, so the focus/scroll
        // below would otherwise find nothing. setState here lands in the
        // same frame the addPostFrameCallback below fires after.
        if (_isPatientDetailsField(target.key)) {
          if (!_patientDetailsExpanded) setState(() => _patientDetailsExpanded = true);
        } else if (!_carePreferencesExpanded) {
          setState(() => _carePreferencesExpanded = true);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          target.focusNode?.requestFocus();
          if (target.focusNode != null) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
          final ctx = target.key.currentContext;
          if (ctx != null && ctx.mounted) {
            await Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
        });
      }
      return;
    }
    if (_hasActiveApplication) {
      final confirmed = await _confirmModifyWithActiveApplicants();
      if (!confirmed) return;
    }
    await _save();
  }

  /// Shown only once the edit is otherwise valid and ready to save, and
  /// only when a candidate has already applied/been accepted — editing is
  /// always allowed (no backend lock any more), but changing the
  /// requirement out from under an existing candidate deserves a deliberate
  /// confirmation, with a nudge to actually talk to them about it first.
  Future<bool> _confirmModifyWithActiveApplicants() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modify this requirement?'),
        content: const Text(
          'There are candidates who applied based on the current details. Are you sure you '
          'want to modify this requirement? We recommend discussing any changes with the '
          'candidates directly before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No, keep it as is'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, modify'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(individualRepositoryProvider).editRequirement(
            widget.requirement.id,
            careReceiver: CareReceiverInput(
              patientName: _patientNameController.text.trim(),
              age: _age!,
              gender: _gender!,
              weightKg: _weightKg!,
              feedingType: _feedingType,
              hasMedicalCondition: !_medicalConditions.contains(_noneMedicalCondition),
              medicalConditions: _medicalConditions.contains(_noneMedicalCondition) ? null : _medicalConditions,
              medicalConditionOther: _medicalConditionOtherController.text.trim(),
              toiletAssistance: _toiletAssistance.isEmpty ? null : _toiletAssistance,
              toiletAssistanceOther: _toiletAssistanceOtherController.text.trim(),
            ),
            city: _city!,
            area: _areaController.text.trim(),
            dutyType: _dutyType!,
            startDate:
                '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
            careDuration: _careDuration!,
            languages: _languages.contains(_noPreferenceLanguage) ? [] : _languages,
            preferredGender: _preferredGender,
            preferredReligion: _preferredReligion,
            frequencyOfCare: _derivedFrequencyOfCare!,
            salaryAmount: _salaryController.text.trim(),
          );
      if (mounted) widget.onSaved();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _hasAcceptedApplicant =>
      widget.applications.any((a) => a.status == JobApplicationStatus.accepted);

  /// Mirrors the backend's own JOB_015 check — cancellable at any point in
  /// the lifecycle except once it's already been terminated some other
  /// way (admin-rejected or already cancelled once).
  bool get _canCancel =>
      !widget.requirement.isCancelled &&
      widget.requirement.rejectionReason == null;

  /// Mirrors the backend's own JOB_017 check — only a requirement this
  /// account cancelled itself can be self-reactivated; an admin-rejected
  /// one never can (same asymmetry as _canCancel above).
  bool get _canReactivate => widget.requirement.isCancelled;

  /// Mirrors the backend's own JOB_014 check (job_applications.status IN
  /// ('applied', 'accepted')) — editing is blocked once a caregiver has
  /// responded, regardless of the requirement's own status. Rejected/
  /// completed applications never count. Every field still renders (see
  /// "show all details by default") but is disabled (IgnorePointer +
  /// reduced opacity below), not hidden.
  bool get _hasActiveApplication => widget.applications.any((a) =>
      a.status == JobApplicationStatus.applied ||
      a.status == JobApplicationStatus.accepted);

  String get _statusLabel {
    switch (widget.requirement.status) {
      case JobStatus.pendingReview:
        return 'Pending admin review';
      case JobStatus.active:
        return 'Live — visible to caregivers';
      case JobStatus.closed:
        if (widget.requirement.isCancelled) return 'Cancelled';
        if (widget.requirement.rejectionReason != null) return 'Rejected';
        return _hasAcceptedApplicant ? 'Closed — caregiver assigned' : 'Closed';
      default:
        return widget.requirement.status;
    }
  }

  Color get _statusColor {
    switch (widget.requirement.status) {
      case JobStatus.pendingReview:
        return AppColors.warning;
      case JobStatus.active:
        return AppColors.success;
      case JobStatus.closed:
        if (widget.requirement.isCancelled) return AppColors.textSecondary;
        return widget.requirement.rejectionReason != null
            ? AppColors.error
            : AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  /// The card's own outer border — red while the job is genuinely live
  /// (active, visible to caregivers right now), grey once it's cancelled
  /// or closed in any way (including pending_review, which isn't yet
  /// visible to caregivers). A different signal from [_statusColor], which
  /// colors the status pill itself.
  Color get _cardBorderColor =>
      widget.requirement.status == JobStatus.active ? AppColors.error : AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final requirement = widget.requirement;
    final careReceiver = requirement.careReceiver;
    // A fixed menu, always offered — each item individually disabled (not
    // hidden) when its own precondition doesn't hold. No Edit action here
    // any more — every field is already editable directly on the card
    // below. The one slot is Reactivate (not Cancel) once the requirement
    // is cancelled — cancelling an already-cancelled one makes no sense,
    // but bringing it back does.
    final menuActions = <_MenuAction>[
      if (widget.requirement.isCancelled)
        _MenuAction(
          label: 'Make Active Again',
          enabled: _canReactivate,
          onSelected: widget.onReactivate,
        )
      else
        _MenuAction(
          label: _canCancel ? 'Cancel the Job' : 'Cancel the Job (Unavailable)',
          enabled: _canCancel,
          destructive: true,
          onSelected: widget.onCancel,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      // A wide border on a light green shade — easier for a senior citizen
      // to see and tell apart from the page background/other cards than
      // the default thin light-grey outline used elsewhere. Red while the
      // job is genuinely live (see _cardBorderColor), grey once it's
      // cancelled or closed — so the border itself signals whether this
      // posting still needs attention.
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _cardBorderColor, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The status badge sits right next to the Job Id (small
              // margin between them) in a Wrap, not squeezed into a
              // Flexible sharing the row with the menu button — a Wrap
              // moves the badge onto its own second line when the row
              // genuinely has no room, rather than truncating a long label
              // like "Live — visible to caregivers" with "…".
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _JobIdLine(requirement: requirement),
                    _StatusBadge(
                      label: _statusLabel,
                      color: _statusColor,
                      blink: requirement.status == JobStatus.active,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_MenuAction>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More options',
                onSelected: (action) => action.onSelected(),
                itemBuilder: (context) => [
                  for (final action in menuActions)
                    PopupMenuItem<_MenuAction>(
                      value: action,
                      enabled: action.enabled,
                      child: Text(
                        action.label,
                        style: action.destructive && action.enabled
                            ? const TextStyle(color: AppColors.error)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (requirement.status == JobStatus.closed &&
              requirement.rejectionReason != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Reason: ${requirement.rejectionReason}',
                style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (careReceiver != null)
            _FieldLine(
              label: 'Type Of Care',
              value: () {
                final live = _careReceiverForTierDerivation ?? careReceiver;
                final tier = deriveCareTier(live);
                return CareTier.displayNames[tier] ?? tier;
              }(),
            ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (careReceiver != null) ...[
                Expanded(
                  child: _FieldLine(
                    label: 'Scope Of Work',
                    value: 'Click Here',
                    isLink: true,
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => ScopeOfWorkDialog(
                        tier: deriveCareTier(_careReceiverForTierDerivation ?? careReceiver),
                        repository: ref.read(scopeOfWorkRepositoryProvider),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: _FieldLine(
                  label: 'Duty Requirements',
                  value: 'Click Here',
                  isLink: true,
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => DutyRequirementsDialog(
                      dutyType: _dutyType ?? requirement.dutyType,
                      repository: ref.read(dutyRequirementsRepositoryProvider),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          // Every field is always directly editable — no lock any more
          // (see "Registration IS posting" in CLAUDE.md for the Individual
          // JOB_014 relaxation). Tapping Save while a candidate has an
          // active application shows a confirmation first instead (see
          // _confirmModifyWithActiveApplicants).
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (careReceiver != null) ...[
                    SectionBox(
                      icon: Icons.person,
                      title: 'Patient Details',
                      collapsible: true,
                      expanded: _patientDetailsExpanded,
                      onToggle: () => setState(() => _patientDetailsExpanded = !_patientDetailsExpanded),
                      children: [
                        TextField(
                          key: _patientNameKey,
                          controller: _patientNameController,
                          focusNode: _patientNameFocusNode,
                          maxLength: Validation.nameMaxLength,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.badge),
                            labelText: "Patient's Name (Mandatory)",
                            border: const OutlineInputBorder(),
                            errorText: _showValidationErrors && !_isPatientNameValid
                                ? 'Enter the patient\'s name (letters only, max ${Validation.nameMaxLength} characters)'
                                : null,
                            suffixIcon: _fieldControls('patientName', _isPatientNameDirty, _revertPatientName),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          key: _ageKey,
                          controller: _ageController,
                          focusNode: _ageFocusNode,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.cake),
                            labelText: "Patient's Age (Mandatory)",
                            border: const OutlineInputBorder(),
                            errorText: _showValidationErrors && !_isAgeValid ? 'Age is required (1-120)' : null,
                            suffixIcon: _fieldControls('age', _isAgeDirty, _revertAge),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<String>(
                          key: _genderKey,
                          isExpanded: true,
                          initialValue: _gender,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.wc),
                            labelText: "Patient's Gender (Mandatory)",
                            border: const OutlineInputBorder(),
                            errorText: _showValidationErrors && !_isGenderValid ? 'Please select a gender' : null,
                            suffixIcon: _fieldControls('gender', _isGenderDirty, _revertGender),
                          ),
                          items: Gender.all.map((g) => DropdownMenuItem(value: g, child: Text(_capitalize(g)))).toList(),
                          onChanged: (value) => setState(() => _gender = value),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          key: _weightKey,
                          controller: _weightController,
                          focusNode: _weightFocusNode,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.monitor_weight_outlined),
                            labelText: "Patient's Weight (kg) (Mandatory)",
                            border: const OutlineInputBorder(),
                            errorText: _showValidationErrors && !_isWeightValid ? 'Weight is required (1-300 kg)' : null,
                            suffixIcon: _fieldControls('weight', _isWeightDirty, _revertWeight),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<String>(
                          key: _cityKey,
                          isExpanded: true,
                          initialValue: _city,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.location_city),
                            labelText: 'City (Mandatory)',
                            border: const OutlineInputBorder(),
                            errorText: _showValidationErrors && !_isCityValid ? 'Please select a city' : null,
                            suffixIcon: _fieldControls('city', _isCityDirty, _revertCity),
                          ),
                          items: City.all.map((c) => DropdownMenuItem(value: c, child: Text(City.displayNames[c] ?? c))).toList(),
                          onChanged: (value) => setState(() => _city = value),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          key: _areaKey,
                          controller: _areaController,
                          focusNode: _areaFocusNode,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.location_on),
                            labelText: 'Area (Mandatory)',
                            border: const OutlineInputBorder(),
                            errorText: _showValidationErrors && !_isAreaValid ? 'Area is required' : null,
                            suffixIcon: _fieldControls('area', _isAreaDirty, _revertArea),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        AreaCharLimitNote(currentLength: _areaController.text.length),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            const Icon(Icons.medical_information, size: 18, color: AppColors.primaryDark),
                            const SizedBox(width: AppSpacing.xs),
                            const Flexible(
                              child: Text('Medical Condition (Mandatory)', style: SectionBox.fieldGroupLabelStyle),
                            ),
                            const Spacer(),
                            if (_isMedicalConditionDirty)
                              _fieldControls('medicalCondition', true, _revertMedicalCondition)!,
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        VitaMultiSelectChips(
                          options: [_noneMedicalCondition, ...MedicalCondition.all],
                          labels: {_noneMedicalCondition: _noneMedicalConditionLabel, ...MedicalCondition.displayNames},
                          selected: _medicalConditions,
                          onChanged: (next) => setState(() {
                            _applyMedicalConditionSelection(next);
                            _refreshSuggestedSalary();
                          }),
                        ),
                        if (_medicalConditions.contains(MedicalCondition.other)) ...[
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            controller: _medicalConditionOtherController,
                            decoration: const InputDecoration(
                              labelText: 'Please describe the other condition',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  SectionBox(
                    icon: Icons.tune,
                    title: 'Care Preferences',
                    collapsible: true,
                    expanded: _carePreferencesExpanded,
                    onToggle: () => setState(() => _carePreferencesExpanded = !_carePreferencesExpanded),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: _dutyTypeKey,
                              isExpanded: true,
                              initialValue: _dutyType,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.access_time),
                                labelText: 'Hours Care Needed (Mandatory)',
                                border: const OutlineInputBorder(),
                                errorText: _showValidationErrors && !_isDutyTypeValid ? 'Please select duty hours' : null,
                                suffixIcon: _fieldControls('dutyType', _isDutyTypeDirty, _revertDutyType),
                              ),
                              items: DutyType.all
                                  .map((d) => DropdownMenuItem(value: d, child: Text(DutyType.displayNames[d] ?? d)))
                                  .toList(),
                              onChanged: (value) => setState(() => _dutyType = value),
                            ),
                          ),
                          DutyRequirementsInfoButton(dutyType: _dutyType),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      KeyedSubtree(
                        key: _startDateKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: _showValidationErrors && !_isStartDateValid
                                      ? AppColors.error
                                      : AppColors.primaryDark,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Flexible(
                                  child: Text(
                                    'Preferred Start Date (Mandatory)',
                                    style: SectionBox.fieldGroupLabelStyle.copyWith(
                                      color: _showValidationErrors && !_isStartDateValid ? AppColors.error : null,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (_isStartDateDirty) _fieldControls('startDate', true, _revertStartDate)!,
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            OutlinedButton.icon(
                              onPressed: _pickStartDate,
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                _startDate == null
                                    ? 'Select date'
                                    : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                              ),
                            ),
                            if (_showValidationErrors && !_isStartDateValid)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text('Select a preferred start date',
                                    style: TextStyle(color: AppColors.error, fontSize: AppTypography.small)),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: _careDurationKey,
                        isExpanded: true,
                        initialValue: _careDuration,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.timelapse),
                          labelText: 'How long you need the care for? (Mandatory)',
                          border: const OutlineInputBorder(),
                          errorText:
                              _showValidationErrors && !_isCareDurationValid ? 'Please select how long care is needed' : null,
                          suffixIcon: _fieldControls('careDuration', _isCareDurationDirty, _revertCareDuration),
                        ),
                        items: CareDuration.all
                            .map((d) => DropdownMenuItem(value: d, child: Text(CareDuration.displayNames[d] ?? d)))
                            .toList(),
                        onChanged: (value) => setState(() {
                          _careDuration = value;
                          _refreshSuggestedSalary();
                        }),
                      ),
                      if (_showShortTermDurationWarning) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.1),
                            border: Border.all(color: AppColors.warning),
                            borderRadius: BorderRadius.circular(AppSpacing.sm),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
                              SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Short-term requirement',
                                      style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Many nurses do not accept short-term assignments. You can '
                                      'continue with this requirement, but you may receive fewer '
                                      "or no applicants. If you don't find a suitable nurse, you "
                                      'may edit this to "Need for minimum a month".',
                                      style: TextStyle(color: AppColors.warning),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: _toiletAssistanceKey,
                        isExpanded: true,
                        initialValue: _toiletAssistance.isEmpty ? null : _toiletAssistance.first,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.wash),
                          labelText: 'Toilet Assistance (Mandatory)',
                          border: const OutlineInputBorder(),
                          errorText:
                              _showValidationErrors && !_isToiletAssistanceValid ? 'Please select toilet assistance' : null,
                          suffixIcon: _fieldControls('toiletAssistance', _isToiletAssistanceDirty, _revertToiletAssistance),
                        ),
                        items: ToiletAssistance.all
                            .map((t) => DropdownMenuItem(value: t, child: Text(ToiletAssistance.displayNames[t] ?? t)))
                            .toList(),
                        onChanged: (value) => setState(() {
                          _toiletAssistance
                            ..clear()
                            ..add(value!);
                          _refreshSuggestedSalary();
                        }),
                      ),
                      if (_toiletAssistance.contains(ToiletAssistance.others)) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _toiletAssistanceOtherController,
                          decoration: const InputDecoration(
                            labelText: 'Please describe the other toilet assistance',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: _feedingTypeKey,
                        isExpanded: true,
                        initialValue: _feedingType,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.restaurant),
                          labelText: 'Feeding/Medicine Assistance (Mandatory)',
                          border: const OutlineInputBorder(),
                          errorText:
                              _showValidationErrors && !_isFeedingTypeValid ? 'Please select feeding/medicine assistance' : null,
                          suffixIcon: _fieldControls('feedingType', _isFeedingTypeDirty, _revertFeedingType),
                        ),
                        items: FeedingType.all
                            .map((f) => DropdownMenuItem(value: f, child: Text(FeedingType.displayNames[f] ?? f)))
                            .toList(),
                        onChanged: (value) => setState(() {
                          _feedingType = value;
                          _refreshSuggestedSalary();
                        }),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _preferredGender,
                        decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.people_outline),
                            labelText: 'Preferred Caregiver Gender',
                            border: const OutlineInputBorder(),
                            suffixIcon: _fieldControls('preferredGender', _isPreferredGenderDirty, _revertPreferredGender)),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('No preference')),
                          DropdownMenuItem(value: Gender.male, child: Text('Male')),
                          DropdownMenuItem(value: Gender.female, child: Text('Female')),
                        ],
                        onChanged: (value) => setState(() => _preferredGender = value),
                      ),
                      if (_showGenderMismatchWarning) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.1),
                            border: Border.all(color: AppColors.warning),
                            borderRadius: BorderRadius.circular(AppSpacing.sm),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
                              SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  'Requesting a female caregiver for a male patient reduces your chances of '
                                  'getting matched by about 90%.',
                                  style: TextStyle(color: AppColors.warning),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'This is just a guidance, you must discuss it directly '
                          'with caregivers. Fees are paid directly to the '
                          'Nurse/Caregivers.',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: AppTypography.caption,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        // Read-only — bold standout text, never user-typed,
                        // same as the registration form's own salary
                        // display (deliberate — see CLAUDE.md's "Account
                        // Deletion"-adjacent Connectivity Banner section
                        // and the salary-bar note under "NurseNow" for
                        // why). Still auto-filled/refreshed from the Rate
                        // Card suggestion (see _refreshSuggestedSalary,
                        // triggered on every Toilet Assistance/Feeding
                        // Type/Medical Condition/Duration change) and still
                        // what gets submitted as salary_amount on Save.
                        SizedBox(
                          key: _salaryKey,
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Salary (₹/${_derivedFrequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month'}) — Guidance only',
                                style: const TextStyle(
                                    fontSize: AppTypography.small,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _salaryController.text.isEmpty ? '—' : _salaryController.text,
                                style: const TextStyle(
                                    fontSize: AppTypography.heading,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary),
                              ),
                              if (_showValidationErrors && !_isSalaryValid) ...[
                                const SizedBox(height: 2),
                                const Text(
                                  'Salary is required',
                                  style: TextStyle(color: AppColors.error, fontSize: AppTypography.caption),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (careReceiver != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _buildDerivedTierLine(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
          // No consolidated Save/Discard bar any more — the tick/cross
          // controls are inline, right next to whichever field was
          // actually touched (see _fieldControls), so they're visible
          // without scrolling to the bottom of a long card. This is just
          // the saving spinner, shown wherever a save triggered from any
          // field is in flight.
          if (_saving) ...[
            const SizedBox(height: AppSpacing.sm),
            const Row(
              children: [
                SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: AppSpacing.sm),
                Text('Saving…', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ],
          if (requirement.status != JobStatus.pendingReview) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            if (requirement.isCancelled)
              const Text(
                'This requirement was cancelled. Candidate applications are no longer available.',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic),
              )
            else
              _ApplicantsSection(
                applications: widget.applications,
                decidingApplicationId: widget.decidingApplicationId,
                onAccept: widget.onAccept,
                onReject: widget.onReject,
                onViewProfile: widget.onViewProfile,
              ),
          ],
        ],
      ),
    );
  }

  /// "Based on the requirements you entered, this appears to be a
  /// `<tier>`." with the tier name itself tappable — opens the Scope of
  /// Work dialog for the exact tier deriveCareTier derives from the card's
  /// current (possibly in-progress-edited) selections.
  Widget _buildDerivedTierLine() {
    final careReceiver = _careReceiverForTierDerivation;
    if (careReceiver == null) return const SizedBox.shrink();
    final tier = deriveCareTier(careReceiver);
    final tierLabel = CareTier.displayNames[tier] ?? tier;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Based on the requirements you entered, this appears to be a ',
          style: TextStyle(color: AppColors.textPrimary, fontSize: AppTypography.small),
        ),
        GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => ScopeOfWorkDialog(
              tier: tier,
              repository: ref.read(scopeOfWorkRepositoryProvider),
            ),
          ),
          child: Text(
            tierLabel,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: AppTypography.small,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const Text('.', style: TextStyle(color: AppColors.textPrimary, fontSize: AppTypography.small)),
      ],
    );
  }
}

/// A prominent, plain-language, color-coded status pill — the single most
/// important thing to communicate at a glance, especially for a senior
/// citizen scanning the card quickly.
/// [blink] is only ever true while the job is genuinely live (active,
/// visible to caregivers right now) — same "needs attention" signal as
/// the card's own red border (_cardBorderColor) and JobDetailCard's
/// BlinkingStartDateBadge on the caregiver-facing side.
class _StatusBadge extends StatefulWidget {
  final String label;
  final Color color;
  final bool blink;

  const _StatusBadge({required this.label, required this.color, this.blink = false});

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(_controller);
    if (widget.blink) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        border: Border.all(color: widget.color, width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      // No overflow/ellipsis — a status label wraps onto a second line
      // rather than ever being truncated with "…"; the pill's own
      // rounded-rect background grows with it (borderRadius 999 still
      // reads as fully rounded ends on a short one-line label, and as a
      // softly rounded rectangle on a wrapped two-line one).
      child: Text(widget.label,
          style: TextStyle(
              color: widget.color, fontWeight: FontWeight.bold, fontSize: AppTypography.subtitle)),
    );
    if (!widget.blink) return badge;
    return FadeTransition(opacity: _opacity, child: badge);
  }
}

/// A single "More options" menu action — [enabled] mirrors the same
/// preconditions the old primary-button/secondary-menu split used to
/// enforce (JOB_014 for editing, the one-live-requirement rule for Post
/// Similar, JOB_015 for cancelling), just always rendered as one of a
/// fixed 3-item menu rather than conditionally shown/hidden.
class _MenuAction {
  final String label;
  final bool enabled;
  final bool destructive;
  final VoidCallback onSelected;

  const _MenuAction({
    required this.label,
    required this.enabled,
    this.destructive = false,
    required this.onSelected,
  });
}

// The label portion (before the colon) of every field line — "Job Id",
// "Type Of Care", "Salary Guidance Range", "Scope Of Work", "Duty
// Requirements" — is bold black, distinct from the dark green value that
// follows it.
const _fieldLabelStyle = TextStyle(
    fontSize: AppTypography.body, color: AppColors.textPrimary, fontWeight: FontWeight.bold);
const _fieldValueStyle = TextStyle(
    fontSize: AppTypography.body, color: AppColors.success, fontWeight: FontWeight.bold);
const _fieldLinkStyle = TextStyle(
    fontSize: AppTypography.body,
    color: AppColors.success,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.underline);

/// The card's primary identifier — the job's real display id, set apart
/// from the "Job Id" label (bold black, like every other field label) in
/// its own larger bold green, same visual weight a hospital chart gives a
/// record/MRN number.
class _JobIdLine extends StatelessWidget {
  final JobModel requirement;

  const _JobIdLine({required this.requirement});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Job Id: ', style: _fieldLabelStyle),
          TextSpan(
            text: jobDisplayId(requirement),
            style: const TextStyle(
                fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold, color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

/// A single, uniformly-styled "Label: Value" record line — the value is
/// either plain text or, when [isLink] is set, a tappable "Click Here"
/// styled like a link, opening whatever [onTap] shows (the derived Scope
/// of Work or Duty Requirements popup). Consistent font size/weight/color
/// across every line of this shape, so the card reads like a clean record
/// rather than a mix of ad hoc chip styles.
class _FieldLine extends StatelessWidget {
  final String label;
  final String value;
  final bool isLink;
  final VoidCallback? onTap;

  const _FieldLine({
    required this.label,
    required this.value,
    this.isLink = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseValueStyle = isLink ? _fieldLinkStyle : _fieldValueStyle;
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: _fieldLabelStyle),
          TextSpan(text: value, style: baseValueStyle),
        ],
      ),
    );
    if (onTap == null) return text;
    return InkWell(onTap: onTap, child: text);
  }
}

/// Shows the total applicant count up front, then every applicant — no
/// candidate's profile/phone is ever hidden, whichever side rejected them
/// (or if the caregiver closed an accepted engagement themselves): the
/// patient/family can always look them up and reconsider. At most one
/// candidate can be `accepted` at a time (JOB_016 backstops this
/// server-side) — the accepted one is pinned to the top; while anyone is
/// accepted, no other candidate offers an Accept action (not even a
/// candidate this account or the caregiver had previously rejected) until
/// that acceptance is undone. Rejecting (declining an undecided candidate,
/// or undoing an acceptance) always requires a reason — see
/// _rejectWithReason.
class _ApplicantsSection extends StatelessWidget {
  final List<JobApplicationModel> applications;
  final Set<String> decidingApplicationId;
  final void Function(String applicationId) onAccept;
  final void Function(String applicationId) onReject;
  final void Function(String applicationId) onViewProfile;

  const _ApplicantsSection({
    required this.applications,
    required this.decidingApplicationId,
    required this.onAccept,
    required this.onReject,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final hasAccepted =
        applications.any((a) => a.status == JobApplicationStatus.accepted);
    final awaitingCount = applications
        .where((a) => a.status == JobApplicationStatus.applied)
        .length;

    // Accepted candidate first (the one engagement that matters most right
    // now), then everyone else by most recent activity.
    final sorted = List<JobApplicationModel>.of(applications)
      ..sort((a, b) {
        final aAccepted = a.status == JobApplicationStatus.accepted;
        final bAccepted = b.status == JobApplicationStatus.accepted;
        if (aAccepted != bAccepted) return aAccepted ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            '${applications.length} candidate${applications.length == 1 ? '' : 's'} applied in total',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.sm),
        if (applications.isEmpty)
          const Text('No applicants yet.',
              style: TextStyle(color: AppColors.textSecondary))
        else ...[
          if (hasAccepted)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'You have accepted a candidate. Reject them to be able to accept someone else.',
                style: TextStyle(
                    color: AppColors.primaryDark, fontWeight: FontWeight.w600),
              ),
            )
          else if (awaitingCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                awaitingCount == 1
                    ? '1 candidate awaiting your decision'
                    : '$awaitingCount candidates awaiting your decision',
                style: const TextStyle(
                    color: AppColors.primaryDark, fontWeight: FontWeight.w600),
              ),
            ),
          for (final application in sorted) ...[
            _ApplicantTile(
              application: application,
              isDeciding: decidingApplicationId.contains(application.id),
              // A completed engagement (the caregiver closed the job
              // themselves after finishing the work) can still be
              // re-accepted — "Accept Anyway", same as a previously
              // rejected candidate — since completeJob already reopens the
              // job to active server-side, there's nothing left to undo
              // first. Anyone already accepted obviously can't be accepted
              // again via this button (see _isAccepted below — Reject-to-
              // undo is the only action offered for them instead), and
              // while someone else is accepted, no one else is offered
              // Accept at all.
              canAccept: !hasAccepted,
              // An undecided candidate is only actionable (accept OR
              // reject) while no one else is accepted — once someone is,
              // the rest are simply on hold, not something you need to
              // actively decline. The currently-accepted candidate's own
              // Reject (undo) always stays available regardless.
              canReject: (application.status == JobApplicationStatus.applied &&
                      !hasAccepted) ||
                  application.status == JobApplicationStatus.accepted,
              onAccept: () => onAccept(application.id),
              onReject: () => onReject(application.id),
              onViewProfile: () => onViewProfile(application.id),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ],
    );
  }
}

class _ApplicantTile extends StatelessWidget {
  final JobApplicationModel application;
  final bool isDeciding;
  final bool canAccept;
  final bool canReject;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onViewProfile;

  const _ApplicantTile({
    required this.application,
    required this.isDeciding,
    required this.canAccept,
    required this.canReject,
    required this.onAccept,
    required this.onReject,
    required this.onViewProfile,
  });

  bool get _isAccepted => application.status == JobApplicationStatus.accepted;
  bool get _isApplied => application.status == JobApplicationStatus.applied;
  bool get _isCompleted => application.status == JobApplicationStatus.completed;
  bool get _isRejected => application.status == JobApplicationStatus.rejected;

  /// A rejected application with no decider is a caregiver's own
  /// withdrawal (closing a job they applied to before being accepted) —
  /// same `decided_by IS NULL` convention used everywhere else to tell a
  /// self-action apart from the patient's own decision.
  bool get _isRejectedByCaregiver =>
      _isRejected && application.decidedBy == null;

  String get _statusLabel {
    if (_isAccepted) return 'Accepted';
    if (_isApplied) return 'Awaiting your decision';
    if (_isCompleted) return 'Closed by Caregiver';
    if (_isRejectedByCaregiver) return 'Rejected by Caregiver';
    return _capitalize(application.status);
  }

  Color get _statusColor {
    if (_isAccepted) return AppColors.success;
    if (_isApplied) return AppColors.warning;
    if (_isRejected) return AppColors.error;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: _isAccepted
            ? AppColors.success.withValues(alpha: 0.08)
            : _isApplied
                ? AppColors.warning.withValues(alpha: 0.08)
                : (_isRejected
                    ? AppColors.error.withValues(alpha: 0.06)
                    : null),
        // Amber/highlighted with a wider border — a candidate waiting on a
        // decision stands out from a plain grey/green/red decided tile at
        // a glance.
        border: Border.all(
          color: _isApplied
              ? AppColors.warning
              : (_statusColor == AppColors.textSecondary
                  ? AppColors.border
                  : _statusColor),
          width: _isApplied ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(application.fullName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (_isAccepted) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.check_circle,
                          color: AppColors.success, size: 16),
                    ] else if (_isApplied) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.hourglass_top,
                          color: AppColors.warning, size: 16),
                    ] else if (_isRejected) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.cancel,
                          color: AppColors.error, size: 16),
                    ],
                  ],
                ),
              ),
              // Capped (not a competing-flex Expanded/Flexible) so it's
              // processed as a plain trailing child — Row gives the
              // Expanded name above ALL remaining space once this is
              // subtracted, which pins the status flush to the tile's
              // right edge rather than splitting the row 50/50. The cap
              // itself is what keeps this safe on a narrow tile: without
              // one, a long label (e.g. "Awaiting your decision") has no
              // bound at all in a Row and can overflow outright.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  _statusLabel,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: _statusColor,
                    fontWeight: (_isAccepted || _isRejected)
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          // The phone number and profile stay visible no matter the
          // outcome — rejected (by either side) or completed candidates
          // are never hidden, so the patient/family can always look them
          // up again and reconsider.
          Text(application.phone,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          _ApplicantTimeline(application),
          const SizedBox(height: AppSpacing.xs),
          if (isDeciding)
            const SizedBox(
                height: 20, width: 20, child: VitaLoadingIndicator(size: 20))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: onViewProfile,
                  icon: const Icon(Icons.person_outline, size: 16),
                  label: const Text('View Profile'),
                ),
                // Expanded + Align(centerRight), not a Spacer()+Flexible
                // pair — a Spacer and a Flexible are BOTH flex children, so
                // Flutter splits the leftover space 50/50 between them
                // regardless of how little the button group actually
                // needs, leaving it short of the tile's true right edge
                // (the same bug the status label above had before it was
                // fixed). A single Expanded absorbing everything, with
                // Align pinning its child to that region's right edge,
                // lines this group up with the status label directly above
                // it. Align also gives the Wrap inside a real bounded
                // width, so it still drops Accept/Reject to their own
                // second line rather than overflow if the tile is too
                // narrow to fit everything on one line.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        if (canAccept)
                          TextButton.icon(
                            onPressed: onAccept,
                            icon: const Icon(Icons.check, size: 16, color: AppColors.success),
                            label: Text(
                              (_isRejected || _isCompleted) ? 'Accept Anyway' : 'Accept',
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: const TextStyle(color: AppColors.success),
                            ),
                          ),
                        if (canReject)
                          TextButton.icon(
                            onPressed: onReject,
                            icon: const Icon(Icons.close, size: 16, color: AppColors.error),
                            label: const Text('Reject', style: TextStyle(color: AppColors.error)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The candidate's full action history on this application — every
/// transition with who did it and exactly when, newest first (the current
/// status is the one worth seeing without scrolling). `decidedByName`, when
/// present, names exactly who accepted/rejected — the patient/family
/// themselves, or an admin who intervened on their behalf via admin-web —
/// rather than a vague "you"/"the employer". A caregiver-initiated close
/// or self-withdrawal (`decidedBy == null`) is always the caregiver's own
/// doing, so those lines never need a name.
class _ApplicantTimeline extends StatefulWidget {
  final JobApplicationModel application;

  const _ApplicantTimeline(this.application);

  @override
  State<_ApplicantTimeline> createState() => _ApplicantTimelineState();
}

class _ApplicantTimelineState extends State<_ApplicantTimeline> {
  // Same fixed per-row heights as caregiver-app's own ApplicationTimeline
  // (job_detail_card.dart) — both parties see the same "4 rows by default,
  // scroll for the rest" treatment.
  static const _fontSize = AppTypography.small;
  static const _rowHeight = 18.0;
  static const _reasonRowHeight = 32.0; // a "Rejected + Reason" row wraps to two lines
  // Strictly less than 5 plain rows and strictly more than 4, so a 5th
  // entry always genuinely overflows and the scrollbar is never shown
  // without something real to scroll to.
  static const _maxHeight = 78.0;

  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final application = widget.application;
    final entries = <MapEntry<DateTime, String>>[];
    if (application.appliedAt != null) {
      final at = DateTime.parse(application.appliedAt!).toLocal();
      entries.add(MapEntry(at, 'Applied: ${_formatDateTime(at)}'));
    }
    if (application.acceptedAt != null) {
      final at = DateTime.parse(application.acceptedAt!).toLocal();
      final by = application.decidedByName != null
          ? ' by ${application.decidedByName}'
          : '';
      entries.add(MapEntry(at, 'Accepted$by: ${_formatDateTime(at)}'));
    }
    // Shown whenever completedAt is set, regardless of the application's
    // CURRENT status — e.g. still shown as history after the candidate is
    // later accepted again ("Accept Anyway") or re-applies, neither of
    // which clear completedAt any more (see
    // OrganisationRequirementApplicationsRepository.upsert/decide).
    if (application.completedAt != null) {
      final at = DateTime.parse(application.completedAt!).toLocal();
      var text = 'Closed by Caregiver: ${_formatDateTime(at)}';
      if (application.closeReason != null) {
        text = '$text\nReason: ${CaregiverCloseReason.displayNames[application.closeReason] ?? application.closeReason}';
      }
      entries.add(MapEntry(at, text));
    }
    // Shown whenever rejectedAt is set, regardless of the application's
    // CURRENT status — same reasoning as completedAt above, so a
    // previously-declined-then-accepted-anyway (or re-applied) candidate's
    // rejection stays visible as history instead of silently vanishing.
    if (application.rejectedAt != null) {
      final at = DateTime.parse(application.rejectedAt!).toLocal();
      final label = application.decidedByName != null
          ? 'Rejected by ${application.decidedByName}'
          : 'Rejected by Caregiver';
      var text = '$label: ${_formatDateTime(at)}';
      if (application.declineReason != null &&
          application.declineReason!.isNotEmpty) {
        text = '$text\nReason: ${application.declineReason!}';
      }
      entries.add(MapEntry(at, text));
    }
    // A candidate can re-apply, then be decided on again — shown last since
    // it always comes after whatever prior outcome it followed.
    if (application.reappliedAt != null) {
      final at = DateTime.parse(application.reappliedAt!).toLocal();
      entries.add(MapEntry(at, 'Re-applied: ${_formatDateTime(at)}'));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    // Newest first — the current status is the one worth seeing without
    // having to scroll for it, same convention as caregiver-app's own
    // ApplicationTimeline.
    entries.sort((a, b) => b.key.compareTo(a.key));

    final totalHeight = entries.fold<double>(
      0,
      (sum, entry) => sum + (entry.value.contains('\n') ? _reasonRowHeight : _rowHeight),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: totalHeight > _maxHeight,
        child: ListView(
          controller: _controller,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            for (final entry in entries)
              SizedBox(
                height: entry.value.contains('\n') ? _reasonRowHeight : _rowHeight,
                child: Text(
                  entry.value,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: _fontSize),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
