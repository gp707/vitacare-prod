import 'dart:convert';

/// Decodes a JWT payload WITHOUT verifying its signature — the server is
/// the source of truth for auth on every request; this is only used
/// client-side to read the `role` claim for UI gating (e.g. showing the
/// Admin Management nav item) and `exp` to avoid showing a stale session.
/// There is no GET /admin/profile endpoint to hydrate this from instead.
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

bool isJwtExpired(String token) {
  final payload = decodeJwtPayload(token);
  final exp = payload['exp'] as int?;
  if (exp == null) return true;
  return DateTime.fromMillisecondsSinceEpoch(exp * 1000).isBefore(DateTime.now());
}
