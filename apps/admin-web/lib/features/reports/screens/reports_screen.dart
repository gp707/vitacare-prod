import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';

/// The 12 cross-cutting operational reports described in CLAUDE.md's Admin
/// Reports section (caregivers idle/no-duty, patients with no applicants,
/// organisations with unconverted applicants, activity rankings, etc.) —
/// grouped by entity type, each with its own admin-typed threshold where
/// relevant.
///
/// [_Report] is a marker interface both per-entity enums implement, so
/// [_ReportsScreenState] can hold a single `_selectedReport` regardless of
/// which group it came from — extending to a third entity group later is
/// just another enum + another arm in each switch.
sealed class _Report {}

enum _CaregiverReport implements _Report { unassignedOrNoDuty, stalledDuty, overThresholdActive, activity }

enum _PatientReport implements _Report { noApplicants, noPendingCandidate, unconvertedApplicants, activity }

enum _OrganisationReport implements _Report { noJobsPosted, noApplicants, unconvertedApplicants, activity }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Report? _selectedReport;
  final _daysController = TextEditingController(text: '7');
  final _minJobsController = TextEditingController(text: '1');
  String _activityOrder = 'desc';

  bool _loading = false;
  String? _errorMessage;
  List<Map<String, dynamic>>? _results;

  @override
  void dispose() {
    _daysController.dispose();
    _minJobsController.dispose();
    super.dispose();
  }

  void _selectReport(_Report report) {
    setState(() {
      _selectedReport = report;
      _results = null;
      _errorMessage = null;
    });
  }

  int? get _days => int.tryParse(_daysController.text.trim());
  int? get _minJobs => int.tryParse(_minJobsController.text.trim());

  bool get _needsDays =>
      _selectedReport == _CaregiverReport.stalledDuty ||
      _selectedReport == _CaregiverReport.activity ||
      _selectedReport == _PatientReport.noApplicants ||
      _selectedReport == _PatientReport.activity ||
      _selectedReport == _OrganisationReport.noApplicants ||
      _selectedReport == _OrganisationReport.activity;

  Future<void> _run() async {
    final report = _selectedReport;
    if (report == null) return;

    if (_needsDays && _days == null) {
      setState(() => _errorMessage = 'Enter a valid number of days');
      return;
    }
    if (report == _CaregiverReport.overThresholdActive && _minJobs == null) {
      setState(() => _errorMessage = 'Enter a valid number of jobs');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(adminReportsRepositoryProvider);
      final results = switch (report) {
        _CaregiverReport.unassignedOrNoDuty => await repo.unassignedOrNoDutyCaregivers(),
        _CaregiverReport.stalledDuty => await repo.stalledDutyCaregivers(_days!),
        _CaregiverReport.overThresholdActive => await repo.overThresholdActiveCaregivers(_minJobs!),
        _CaregiverReport.activity => await repo.caregiverActivity(_days!, order: _activityOrder),
        _PatientReport.noApplicants => await repo.patientsWithNoApplicants(_days!),
        _PatientReport.noPendingCandidate => await repo.patientsWithNoPendingCandidate(),
        _PatientReport.unconvertedApplicants => await repo.patientsWithUnconvertedApplicants(),
        _PatientReport.activity => await repo.patientActivity(_days!, order: _activityOrder),
        _OrganisationReport.noJobsPosted => await repo.organisationsWithNoJobsPosted(),
        _OrganisationReport.noApplicants => await repo.organisationsWithNoApplicants(_days!),
        _OrganisationReport.unconvertedApplicants => await repo.organisationsWithUnconvertedApplicants(),
        _OrganisationReport.activity => await repo.organisationActivity(_days!, order: _activityOrder),
      };
      if (mounted) setState(() => _results = results);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCaregiver(String profileId) {
    Navigator.of(context).pushNamed('/caregiver-detail', arguments: profileId);
  }

  void _openIndividual(String userId) {
    Navigator.of(context).pushNamed('/individual-detail', arguments: userId);
  }

  void _openOrganisation(String userId) {
    Navigator.of(context).pushNamed('/organisation-detail', arguments: userId);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.reports,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reports', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReportGroup(
                        title: 'Caregivers',
                        children: [
                          _ReportTile(
                            label: 'Unassigned or No Duty',
                            selected: _selectedReport == _CaregiverReport.unassignedOrNoDuty,
                            onTap: () => _selectReport(_CaregiverReport.unassignedOrNoDuty),
                          ),
                          _ReportTile(
                            label: 'Assigned, Duty Not Completed in N Days',
                            selected: _selectedReport == _CaregiverReport.stalledDuty,
                            onTap: () => _selectReport(_CaregiverReport.stalledDuty),
                          ),
                          _ReportTile(
                            label: 'More Than X Jobs Accepted, Not Completed',
                            selected: _selectedReport == _CaregiverReport.overThresholdActive,
                            onTap: () => _selectReport(_CaregiverReport.overThresholdActive),
                          ),
                          _ReportTile(
                            label: 'Caregiver Activity (Most/Least Active)',
                            selected: _selectedReport == _CaregiverReport.activity,
                            onTap: () => _selectReport(_CaregiverReport.activity),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ReportGroup(
                        title: 'Patients/Family',
                        children: [
                          _ReportTile(
                            label: 'No Caregiver Applied in N Days',
                            selected: _selectedReport == _PatientReport.noApplicants,
                            onTap: () => _selectReport(_PatientReport.noApplicants),
                          ),
                          _ReportTile(
                            label: 'Live Job, No Pending Candidate',
                            selected: _selectedReport == _PatientReport.noPendingCandidate,
                            onTap: () => _selectReport(_PatientReport.noPendingCandidate),
                          ),
                          _ReportTile(
                            label: 'Applicants Came, None Accepted',
                            selected: _selectedReport == _PatientReport.unconvertedApplicants,
                            onTap: () => _selectReport(_PatientReport.unconvertedApplicants),
                          ),
                          _ReportTile(
                            label: 'Patient Activity (Most/Least Active)',
                            selected: _selectedReport == _PatientReport.activity,
                            onTap: () => _selectReport(_PatientReport.activity),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ReportGroup(
                        title: 'Rehab/Hospitals',
                        children: [
                          _ReportTile(
                            label: 'No Jobs Posted, Ever',
                            selected: _selectedReport == _OrganisationReport.noJobsPosted,
                            onTap: () => _selectReport(_OrganisationReport.noJobsPosted),
                          ),
                          _ReportTile(
                            label: 'Requirements Posted, No Applicant in N Days',
                            selected: _selectedReport == _OrganisationReport.noApplicants,
                            onTap: () => _selectReport(_OrganisationReport.noApplicants),
                          ),
                          _ReportTile(
                            label: 'Applicants Came, None Accepted',
                            selected: _selectedReport == _OrganisationReport.unconvertedApplicants,
                            onTap: () => _selectReport(_OrganisationReport.unconvertedApplicants),
                          ),
                          _ReportTile(
                            label: 'Organisation Activity (Most/Least Active)',
                            selected: _selectedReport == _OrganisationReport.activity,
                            onTap: () => _selectReport(_OrganisationReport.activity),
                          ),
                        ],
                      ),
                      if (_selectedReport != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        const Divider(),
                        const SizedBox(height: AppSpacing.md),
                        _buildParams(),
                        const SizedBox(height: AppSpacing.md),
                        ElevatedButton(onPressed: _loading ? null : _run, child: const Text('Run')),
                        const SizedBox(height: AppSpacing.md),
                        if (_errorMessage != null)
                          Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
                        if (_loading) const Center(child: VitaLoadingIndicator()),
                        if (!_loading && _results != null) _buildResults(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParams() {
    final report = _selectedReport!;
    if (report == _CaregiverReport.unassignedOrNoDuty ||
        report == _PatientReport.noPendingCandidate ||
        report == _PatientReport.unconvertedApplicants ||
        report == _OrganisationReport.noJobsPosted ||
        report == _OrganisationReport.unconvertedApplicants) {
      return const SizedBox.shrink();
    }
    if (report == _CaregiverReport.overThresholdActive) {
      return SizedBox(
        width: 200,
        child: TextField(
          controller: _minJobsController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'More than X jobs', border: OutlineInputBorder()),
        ),
      );
    }
    final needsOrder = report == _CaregiverReport.activity ||
        report == _PatientReport.activity ||
        report == _OrganisationReport.activity;
    if (!needsOrder) {
      // stalledDuty, patients.noApplicants, organisations.noApplicants — Days only.
      return SizedBox(
        width: 200,
        child: TextField(
          controller: _daysController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Days', border: OutlineInputBorder()),
        ),
      );
    }
    return Wrap(
      spacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 200,
          child: TextField(
            controller: _daysController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Days', border: OutlineInputBorder()),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: _activityOrder,
          decoration: const InputDecoration(labelText: 'Order', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'desc', child: Text('Most active first')),
            DropdownMenuItem(value: 'asc', child: Text('Least active first')),
          ],
          onChanged: (value) => setState(() => _activityOrder = value ?? 'desc'),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final results = _results!;
    if (results.isEmpty) {
      return const Text('No results.', style: TextStyle(color: AppColors.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${results.length} result${results.length == 1 ? '' : 's'}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.sm),
        for (final row in results) ...[
          _buildResultRow(row),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }

  Widget _buildResultRow(Map<String, dynamic> row) {
    final report = _selectedReport!;
    if (report is _CaregiverReport) return _buildCaregiverRow(report, row);
    if (report is _PatientReport) return _buildPatientRow(report, row);
    return _buildOrganisationRow(report as _OrganisationReport, row);
  }

  Widget _buildCaregiverRow(_CaregiverReport report, Map<String, dynamic> row) {
    final Widget subtitle = switch (report) {
      _CaregiverReport.unassignedOrNoDuty => Row(
          children: [
            VitaStatusBadge(status: row['verification_status'] as String),
            const SizedBox(width: AppSpacing.xs),
            Text(
              row['ever_had_duty'] == true ? 'Previously had a duty' : 'Never had a duty',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      _CaregiverReport.stalledDuty => Text(
          '${_engagementLabel(row)} · Accepted ${row['days_since_accepted']} days ago',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      _CaregiverReport.overThresholdActive => Text(
          '${row['accepted_count']} accepted jobs, not completed',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      _CaregiverReport.activity => Text(
          '${row['activity_count']} application(s) in the window',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
    };
    return _ResultCard(
      title: '${caregiverDisplayId(row['caregiver_number'] as int?)} · ${row['full_name']}',
      phone: row['phone'] as String,
      subtitle: subtitle,
      onTap: () => _openCaregiver(row['profile_id'] as String),
    );
  }

  Widget _buildPatientRow(_PatientReport report, Map<String, dynamic> row) {
    final Widget subtitle = switch (report) {
      _PatientReport.noApplicants => Text(
          '${_jobLabel(row)} · No applicants in the window',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      _PatientReport.noPendingCandidate => Text(
          '${_jobLabel(row)} · Nothing pending review',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      _PatientReport.unconvertedApplicants => Text(
          '${_jobLabel(row)} · ${row['applicant_count']} applicant(s), none accepted',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      _PatientReport.activity => Text(
          '${row['activity_count']} job(s) posted in the window',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
    };
    return _ResultCard(
      title: '${patientDisplayId(row['patient_number'] as int?)} · ${row['full_name']}',
      phone: row['phone'] as String,
      subtitle: subtitle,
      onTap: () => _openIndividual(row['user_id'] as String),
    );
  }

  Widget _buildOrganisationRow(_OrganisationReport report, Map<String, dynamic> row) {
    final Widget subtitle = switch (report) {
      _OrganisationReport.noJobsPosted => const Text(
          'No requirements posted, ever',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      _OrganisationReport.noApplicants => Text(
          '${row['live_requirement_count']} live requirement(s) · No applicants in the window',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      _OrganisationReport.unconvertedApplicants => Text(
          '${row['applicant_count']} applicant(s), none accepted',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      _OrganisationReport.activity => Text(
          '${row['activity_count']} requirement(s) posted in the window',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
    };
    return _ResultCard(
      title: '${organisationDisplayId(row['org_number'] as int?)} · ${row['organisation_name']}',
      phone: row['phone'] as String,
      subtitle: subtitle,
      onTap: () => _openOrganisation(row['user_id'] as String),
    );
  }

  String _engagementLabel(Map<String, dynamic> row) {
    if (row['engagement_type'] == 'requirement') {
      return 'ORG-JOB-${row['requirement_number']}';
    }
    final patientJobNumber = row['patient_job_number'] as int?;
    final adminJobNumber = row['admin_job_number'] as int?;
    if (patientJobNumber != null) return 'PAT-JOB-$patientJobNumber';
    if (adminJobNumber != null) return 'ADMIN-JOB-$adminJobNumber';
    return 'Job #${row['job_number']}';
  }

  String _jobLabel(Map<String, dynamic> row) {
    final patientJobNumber = row['patient_job_number'] as int?;
    final adminJobNumber = row['admin_job_number'] as int?;
    if (patientJobNumber != null) return 'PAT-JOB-$patientJobNumber';
    if (adminJobNumber != null) return 'ADMIN-JOB-$adminJobNumber';
    return 'Job #${row['job_number']}';
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final String phone;
  final Widget subtitle;
  final VoidCallback onTap;

  const _ResultCard({required this.title, required this.phone, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSpacing.sm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(phone, style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  subtitle,
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ReportGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ReportGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        initiallyExpanded: true,
        children: children,
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ReportTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      selected: selected,
      selectedTileColor: AppColors.primaryLight,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? AppColors.primary : AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
