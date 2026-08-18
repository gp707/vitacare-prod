sealed class SessionState {
  const SessionState();
}

class SessionLoading extends SessionState {
  const SessionLoading();
}

class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

/// No verification pipeline like a caregiver has — an individual account
/// is either logged in or it isn't. [isJobPostingBlocked] gates the "post a
/// requirement" action client-side (the server also enforces it, JOB_010).
class SessionAuthenticated extends SessionState {
  final String fullName;
  final String phone;
  final bool isJobPostingBlocked;

  const SessionAuthenticated({
    required this.fullName,
    required this.phone,
    required this.isJobPostingBlocked,
  });
}
