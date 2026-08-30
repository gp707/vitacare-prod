import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class RateCardRepository {
  final Dio _dio;

  RateCardRepository(this._dio);

  /// Public — no auth required, matches GET /rate-card server-side.
  Future<RateCardModel> get() async {
    final res = await _dio.get(ApiRoutes.rateCard);
    return RateCardModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }
}
