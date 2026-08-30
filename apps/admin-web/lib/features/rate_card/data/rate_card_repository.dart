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

  Future<RateCardWithUpdater> get() async {
    try {
      final res = await _dio.get('/admin/rate-card');
      return RateCardWithUpdater.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(RateCardModel rateCard) async {
    try {
      await _dio.patch('/admin/rate-card', data: rateCard.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
