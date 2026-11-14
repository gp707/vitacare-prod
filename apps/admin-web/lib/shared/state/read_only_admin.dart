import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/state/session_notifier.dart';
import '../../features/auth/state/session_state.dart';

/// True when the signed-in admin is a read-only admin. Screens hide write
/// actions with this; the API refuses them regardless (AUTH_018).
final isReadOnlyAdminProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  return session is AdminSessionAuthenticated && session.isReadOnlyAdmin;
});
