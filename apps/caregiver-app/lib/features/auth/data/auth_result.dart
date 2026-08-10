/// Shape shared by /auth/register and /auth/login/code responses
/// (SPEC.md section 6.3). [profileId] is only present on register.
class AuthResult {
  final String userId;
  final String? profileId;
  final String accessToken;
  final String refreshToken;
  final String verificationStatus;
  final bool advancedDetailsCompleted;

  const AuthResult({
    required this.userId,
    this.profileId,
    required this.accessToken,
    required this.refreshToken,
    required this.verificationStatus,
    required this.advancedDetailsCompleted,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      userId: json['user_id'] as String,
      profileId: json['profile_id'] as String?,
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      verificationStatus: json['verification_status'] as String,
      advancedDetailsCompleted: json['advanced_details_completed'] as bool? ?? false,
    );
  }
}
