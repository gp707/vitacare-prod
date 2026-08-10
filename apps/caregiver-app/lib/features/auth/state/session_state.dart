sealed class SessionState {
  const SessionState();
}

class SessionLoading extends SessionState {
  const SessionLoading();
}

class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

class SessionAuthenticated extends SessionState {
  final String fullName;
  final String phone;
  final String verificationStatus;
  final bool advancedDetailsCompleted;
  final bool hasRequiredDocuments;
  final String? rejectionMessage;

  const SessionAuthenticated({
    required this.fullName,
    required this.phone,
    required this.verificationStatus,
    required this.advancedDetailsCompleted,
    required this.hasRequiredDocuments,
    this.rejectionMessage,
  });

  SessionAuthenticated copyWith({String? verificationStatus, String? rejectionMessage}) {
    return SessionAuthenticated(
      fullName: fullName,
      phone: phone,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      advancedDetailsCompleted: advancedDetailsCompleted,
      hasRequiredDocuments: hasRequiredDocuments,
      // Always taken from the fresh value (not merged with the old one) —
      // this is only ever called from refreshStatus, which always has an
      // up-to-date rejectionMessage (including null once no longer rejected).
      rejectionMessage: rejectionMessage,
    );
  }
}
