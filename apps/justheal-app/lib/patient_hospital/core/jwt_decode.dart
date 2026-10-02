import 'dart:convert';

/// Decodes a JWT payload WITHOUT verifying its signature — the server is
/// the source of truth for auth on every request; this is only used
/// client-side to read the `role` claim right after login/registration, so
/// the app knows whether to hydrate via IndividualRepository or
/// OrganisationRepository (POST /auth/login/code is shared across both
/// account types and doesn't say which one in its response body). Same
/// pattern as admin-web's core/jwt_decode.dart.
Map<String, dynamic> decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw const FormatException('Not a valid JWT');
  }
  var payload = parts[1];
  payload = payload.replaceAll('-', '+').replaceAll('_', '/');
  switch (payload.length % 4) {
    case 2:
      payload += '==';
    case 3:
      payload += '=';
  }
  final decoded = utf8.decode(base64.decode(payload));
  return jsonDecode(decoded) as Map<String, dynamic>;
}
