/// Shape shared by /auth/register/individual and /auth/login/code
/// responses for an individual account. Unlike caregiver's AuthResult,
/// there's no verification_status — individual accounts have no
/// verification pipeline.
class AuthResult {
  final String userId;
  final String accessToken;
  final String refreshToken;

  const AuthResult({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      userId: json['user_id'] as String,
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
    );
  }
}
