import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class UpdateRequiredInfo {
  final String? storeUrl;
  final String? message;

  const UpdateRequiredInfo({this.storeUrl, this.message});
}

class AppVersionRepository {
  final Dio _dio;

  AppVersionRepository(this._dio);

  /// Called once on every cold launch, before the splash screen loads the
  /// session — this is why it's unauthenticated (GET /app-versions/check
  /// takes no token). Returns null when no update is required. Deliberately
  /// fails open on any error (network down, backend unreachable, unexpected
  /// response shape): a broken version check must never be the thing that
  /// locks every user out of the app. This is the single real check for
  /// the whole JustHeal binary (covers both the caregiver and patient/
  /// hospital flows) — it used to pass an `app` bucket so NurseJobs and
  /// NurseNow could be force-upgraded independently (migration 068), back
  /// when they shipped as two separate binaries; collapsed to one
  /// platform-only check by migration 074 once they merged into one.
  Future<UpdateRequiredInfo?> checkForUpdate() async {
    try {
      // defaultTargetPlatform (not dart:io Platform) so this still compiles
      // and runs for the web dev target used to test this app in Chrome.
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? AppPlatform.ios : AppPlatform.android;
      final packageInfo = await PackageInfo.fromPlatform();

      final res = await _dio.get(ApiRoutes.appVersionCheck, queryParameters: {
        'platform': platform,
        'version': packageInfo.version,
      });
      final data = res.data['data'] as Map<String, dynamic>;
      if (data['update_required'] != true) return null;

      return UpdateRequiredInfo(
        storeUrl: data['store_url'] as String?,
        message: data['update_message'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
