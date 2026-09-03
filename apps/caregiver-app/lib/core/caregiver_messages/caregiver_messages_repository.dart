import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class CaregiverMessagesRepository {
  final Dio _dio;

  CaregiverMessagesRepository(this._dio);

  /// Public — no auth required, matches GET /caregiver-messages
  /// server-side. Fetched fresh on every Messages bell load (not cached),
  /// same convention as RateCardButton/ScopeOfWorkButton/
  /// DutyRequirementsButton.
  Future<List<CaregiverMessageModel>> get() async {
    final res = await _dio.get(ApiRoutes.caregiverMessages);
    return (res.data['data'] as List)
        .map((json) => CaregiverMessageModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
