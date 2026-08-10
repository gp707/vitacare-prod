import 'package:firebase_messaging/firebase_messaging.dart';
import '../../features/profile/data/profile_repository.dart';

/// Registers this device for push notifications (SPEC.md 6.4/CLAUDE.md:
/// caregivers get FCM push, not email). Call [register] after registration,
/// on each app launch once authenticated, and after login — [register]
/// itself also subscribes to token-refresh so re-registration after that
/// point is automatic.
class FcmService {
  final ProfileRepository _profileRepository;
  bool _refreshListenerAttached = false;

  FcmService(this._profileRepository);

  Future<void> register() async {
    // Everything here — including just accessing FirebaseMessaging.instance
    // — throws on platforms where Firebase.initializeApp() wasn't
    // configured (this app only ships google-services.json for Android; the
    // Chrome dev target has no Firebase web config). Best-effort: a
    // caregiver without push notifications set up yet can still use every
    // other part of the app (same pattern as SessionNotifier.refreshStatus's
    // pull-to-refresh).
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _profileRepository.updateFcmToken(token);
      }

      if (!_refreshListenerAttached) {
        _refreshListenerAttached = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          try {
            await _profileRepository.updateFcmToken(newToken);
          } catch (_) {
            // Best-effort, same as above.
          }
        });
      }
    } catch (_) {
      // Best-effort, see comment above.
    }
  }
}
