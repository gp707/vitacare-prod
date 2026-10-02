sealed class SessionState {
  const SessionState();
}

class SessionLoading extends SessionState {
  const SessionLoading();
}

class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

/// A stored token exists but couldn't be verified against the server on
/// this launch due to a transient problem (no connectivity, the backend
/// briefly unreachable, a 5xx) — as opposed to the server actively
/// rejecting the token (AUTH_004/AUTH_005), which does mean logging out.
/// The token is deliberately left in storage so a retry (or the next
/// launch) can still succeed instead of forcing a needless re-login for a
/// problem that had nothing to do with whether the token itself is valid.
class SessionLoadError extends SessionState {
  final String message;

  const SessionLoadError(this.message);
}

class SessionAuthenticated extends SessionState {
  final String fullName;
  final String phone;
  final String verificationStatus;
  final bool hasRequiredDocuments;
  final String? rejectionMessage;

  const SessionAuthenticated({
    required this.fullName,
    required this.phone,
    required this.verificationStatus,
    required this.hasRequiredDocuments,
    this.rejectionMessage,
  });

  SessionAuthenticated copyWith({String? verificationStatus, String? rejectionMessage}) {
    return SessionAuthenticated(
      fullName: fullName,
      phone: phone,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      hasRequiredDocuments: hasRequiredDocuments,
      // Always taken from the fresh value (not merged with the old one) —
      // this is only ever called from refreshStatus, which always has an
      // up-to-date rejectionMessage (including null once no longer rejected).
      rejectionMessage: rejectionMessage,
    );
  }
}
