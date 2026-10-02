import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class RateCardRepository {
  final Dio _dio;

  RateCardRepository(this._dio);

  /// Public — no auth required, matches GET /rate-card server-side.
  /// Always exactly 2 entries, one per frequency ('daily'/'monthly').
  Future<List<RateCardModel>> get() async {
    final res = await _dio.get(ApiRoutes.rateCard);
    return (res.data['data'] as List)
        .map((e) => RateCardModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
