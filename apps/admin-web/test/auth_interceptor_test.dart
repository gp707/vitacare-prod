import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/network/api_interceptors.dart';
import 'package:admin_web/core/storage/local_storage.dart';

DioException _error(int status, String code) {
  final options = RequestOptions(path: '/admin/jobs');
  return DioException(
    requestOptions: options,
    response: Response(
      requestOptions: options,
      statusCode: status,
      data: {
        'success': false,
        'error': {'code': code, 'message': 'x'},
      },
    ),
  );
}

/// A handler whose "request failed" result is swallowed — Dio reports a passed-on
/// error through this future, which would otherwise surface as an unhandled error.
ErrorInterceptorHandler _handler() {
  final handler = ErrorInterceptorHandler();
  unawaited(handler.future.then((_) {}, onError: (_) {}));
  return handler;
}

void main() {
  late LocalStorage storage;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorage.create();
  });

  Future<int> endedCount(DioException err) async {
    var ended = 0;
    final interceptor = AuthInterceptor(storage, onSessionEnded: () => ended++);
    interceptor.onError(err, _handler());
    return ended;
  }

  test('an expired or invalid token (AUTH_005) ends the session', () async {
    expect(await endedCount(_error(401, 'AUTH_005')), 1);
  });

  test('a deactivated account (AUTH_004) ends the session', () async {
    expect(await endedCount(_error(401, 'AUTH_004')), 1);
  });

  test('a wrong password at login (AUTH_003), a refusal (403) or a server error do not', () async {
    expect(await endedCount(_error(401, 'AUTH_003')), 0);
    expect(await endedCount(_error(403, 'AUTH_018')), 0);
    expect(await endedCount(_error(500, 'GEN_003')), 0);
  });

  test('without a callback nothing happens (no crash)', () async {
    final interceptor = AuthInterceptor(storage);
    expect(() => interceptor.onError(_error(401, 'AUTH_005'), _handler()), returnsNormally);
  });
}
