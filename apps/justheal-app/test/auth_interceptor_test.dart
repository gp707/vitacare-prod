import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nursenow_app/patient_hospital/core/network/api_interceptors.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';

DioException _errorWithCode(String code) {
  final requestOptions = RequestOptions(path: '/whatever');
  return DioException(
    requestOptions: requestOptions,
    response: Response(
      requestOptions: requestOptions,
      statusCode: 401,
      data: {
        'success': false,
        'error': {'code': code, 'message': 'irrelevant'},
      },
    ),
  );
}

/// ErrorInterceptorHandler.next() completes its internal Completer with an
/// error — left unconsumed, that's an unhandled async error that fails the
/// test even when the assertion under test passed. Every call site below
/// needs its handler's own future drained (.ignore() marks it as
/// deliberately not awaited, same as Future's own dart:async extension)
/// since none of these tests care about the propagated error itself except
/// the one that explicitly asserts on it.
ErrorInterceptorHandler _handler() {
  final handler = ErrorInterceptorHandler();
  // ignore: invalid_use_of_protected_member
  handler.future.ignore();
  return handler;
}

void main() {
  late LocalStorage localStorage;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    localStorage = await LocalStorage.create();
  });

  test('calls onUnauthorized for AUTH_005 (invalid/expired token)', () {
    var called = false;
    final interceptor = AuthInterceptor(localStorage, onUnauthorized: () => called = true);

    interceptor.onError(_errorWithCode('AUTH_005'), _handler());

    expect(called, isTrue);
  });

  test('calls onUnauthorized for AUTH_004 (account deactivated/blocked)', () {
    var called = false;
    final interceptor = AuthInterceptor(localStorage, onUnauthorized: () => called = true);

    interceptor.onError(_errorWithCode('AUTH_004'), _handler());

    expect(called, isTrue);
  });

  test('does not call onUnauthorized for an unrelated error code (e.g. a validation error)', () {
    var called = false;
    final interceptor = AuthInterceptor(localStorage, onUnauthorized: () => called = true);

    interceptor.onError(_errorWithCode('GEN_001'), _handler());

    expect(called, isFalse);
  });

  test('does not call onUnauthorized for AUTH_007 (wrong role, not an invalid token)', () {
    var called = false;
    final interceptor = AuthInterceptor(localStorage, onUnauthorized: () => called = true);

    interceptor.onError(_errorWithCode('AUTH_007'), _handler());

    expect(called, isFalse);
  });

  test('still forwards the error to the next handler either way (screens keep their own error handling)', () {
    final interceptor = AuthInterceptor(localStorage, onUnauthorized: () {});
    final handler = ErrorInterceptorHandler();

    interceptor.onError(_errorWithCode('AUTH_005'), handler);

    // Dio's ErrorInterceptorHandler.next() completes its future with an
    // internal (unexported) wrapper around the DioException — the exact
    // type isn't reachable from here, but the point is that it errors at
    // all, confirming the original error still propagates onward rather
    // than being swallowed by this interceptor.
    // ignore: invalid_use_of_protected_member
    expect(handler.future, throwsA(anything));
  });

  test('does not throw when onUnauthorized is null (not every ApiClient supplies one)', () {
    final interceptor = AuthInterceptor(localStorage);
    expect(() => interceptor.onError(_errorWithCode('AUTH_005'), _handler()), returnsNormally);
  });
}
