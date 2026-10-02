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
  /// locks every Individual/Organisation account out of the app.
  /// Mirrors caregiver-app's own AppVersionRepository exactly, except this
  /// app identifies itself as LoginApp.nursenow so admin can force-upgrade
  /// NurseNow independently of NurseJobs (see migration 068).
  Future<UpdateRequiredInfo?> checkForUpdate() async {
    try {
      // defaultTargetPlatform (not dart:io Platform) so this still compiles
      // and runs for the web dev target used to test this app in Chrome.
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? AppPlatform.ios : AppPlatform.android;
      final packageInfo = await PackageInfo.fromPlatform();

      final res = await _dio.get(ApiRoutes.appVersionCheck, queryParameters: {
        'app': LoginApp.nursenow,
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
