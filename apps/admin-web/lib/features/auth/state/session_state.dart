sealed class AdminSessionState {
  const AdminSessionState();
}

class AdminSessionLoading extends AdminSessionState {
  const AdminSessionLoading();
}

class AdminSessionUnauthenticated extends AdminSessionState {
  const AdminSessionUnauthenticated();
}

class AdminSessionAuthenticated extends AdminSessionState {
  final String userId;
  final String role;

  const AdminSessionAuthenticated({required this.userId, required this.role});

  bool get isSuperAdmin => role == 'super_admin';
}
