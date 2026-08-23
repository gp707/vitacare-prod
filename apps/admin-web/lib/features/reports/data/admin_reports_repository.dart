import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

/// Backs the Reports screen's ~12 operational queries (see CLAUDE.md's
/// Admin Reports section). Deliberately returns loose `List<Map<String,
/// dynamic>>` rows rather than one bespoke model class per report — each
/// report has a different column set, and a flat map is a lower-maintenance
/// fit for a screen this wide than 12 near-identical model classes.
class AdminReportsRepository {
  final Dio _dio;

  AdminReportsRepository(this._dio);

  Future<List<Map<String, dynamic>>> _get(String path, [Map<String, dynamic>? queryParameters]) async {
    try {
      final res = await _dio.get(path, queryParameters: queryParameters);
      return (res.data['data'] as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> unassignedOrNoDutyCaregivers() =>
      _get('/admin/reports/caregivers/unassigned-or-no-duty');

  Future<List<Map<String, dynamic>>> stalledDutyCaregivers(int days) =>
      _get('/admin/reports/caregivers/stalled-duty', {'days': days});

  Future<List<Map<String, dynamic>>> overThresholdActiveCaregivers(int minJobs) =>
      _get('/admin/reports/caregivers/over-threshold-active', {'min_jobs': minJobs});

  Future<List<Map<String, dynamic>>> caregiverActivity(int days, {String order = 'desc'}) =>
      _get('/admin/reports/caregivers/activity', {'days': days, 'order': order});

  Future<List<Map<String, dynamic>>> patientsWithNoApplicants(int days) =>
      _get('/admin/reports/patients/no-applicants', {'days': days});

  Future<List<Map<String, dynamic>>> patientsWithNoPendingCandidate() =>
      _get('/admin/reports/patients/no-pending-candidate');

  Future<List<Map<String, dynamic>>> patientsWithUnconvertedApplicants() =>
      _get('/admin/reports/patients/unconverted-applicants');

  Future<List<Map<String, dynamic>>> patientActivity(int days, {String order = 'desc'}) =>
      _get('/admin/reports/patients/activity', {'days': days, 'order': order});

  Future<List<Map<String, dynamic>>> organisationsWithNoJobsPosted() =>
      _get('/admin/reports/organisations/no-jobs-posted');

  Future<List<Map<String, dynamic>>> organisationsWithNoApplicants(int days) =>
      _get('/admin/reports/organisations/no-applicants', {'days': days});

  Future<List<Map<String, dynamic>>> organisationsWithUnconvertedApplicants() =>
      _get('/admin/reports/organisations/unconverted-applicants');

  Future<List<Map<String, dynamic>>> organisationActivity(int days, {String order = 'desc'}) =>
      _get('/admin/reports/organisations/activity', {'days': days, 'order': order});
}
