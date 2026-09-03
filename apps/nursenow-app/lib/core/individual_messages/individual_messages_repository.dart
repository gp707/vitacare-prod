import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class IndividualMessagesRepository {
  final Dio _dio;

  IndividualMessagesRepository(this._dio);

  /// Public — no auth required, matches GET /individual-messages
  /// server-side. Fetched fresh on every Messages tab load (not cached),
  /// same convention as RateCardButton/ScopeOfWorkButton/
  /// DutyRequirementsButton.
  Future<List<IndividualMessageModel>> get() async {
    final res = await _dio.get(ApiRoutes.individualMessages);
    return (res.data['data'] as List)
        .map((json) => IndividualMessageModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
