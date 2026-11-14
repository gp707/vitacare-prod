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

  /// The limited back-office role: sees most of the console, writes only a
  /// short allow-list (notes, PIN reset, tickets, approving jobs). The API
  /// enforces it; the UI uses this to hide what would only be refused.
  bool get isReadOnlyAdmin => role == 'read_only_admin';
}
