import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class RateCardWithUpdater {
  final RateCardModel rateCard;
  final String? updatedByName;
  final String updatedAt;

  const RateCardWithUpdater({
    required this.rateCard,
    this.updatedByName,
    required this.updatedAt,
  });

  factory RateCardWithUpdater.fromJson(Map<String, dynamic> json) => RateCardWithUpdater(
        rateCard: RateCardModel.fromJson(json),
        updatedByName: json['updated_by_name'] as String?,
        updatedAt: json['updated_at'] as String,
      );
}

class RateCardRepository {
  final Dio _dio;

  RateCardRepository(this._dio);

  /// Always exactly 2 entries, one per frequency ('daily'/'monthly').
  Future<List<RateCardWithUpdater>> get() async {
    try {
      final res = await _dio.get('/admin/rate-card');
      return (res.data['data'] as List)
          .map((e) => RateCardWithUpdater.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(String frequency, RateCardModel rateCard) async {
    try {
      await _dio.patch('/admin/rate-card/$frequency', data: rateCard.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
