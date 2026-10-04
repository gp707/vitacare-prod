import 'package:firebase_messaging/firebase_messaging.dart';
import '../../features/individual/data/individual_repository.dart';
import '../../features/organisation/data/organisation_repository.dart';

/// Registers this device for push notifications — mirrors caregiver-app's
/// own lib/caregiver/core/fcm/fcm_service.dart exactly, except which
/// repository the token is sent to depends on the account's role (Individual
/// vs Organisation aren't known until SessionNotifier has decoded the JWT,
/// so [register] takes [isOrganisation] explicitly rather than deciding it
/// itself). Call [register] after registration and right after
/// SessionNotifier resolves an authenticated session — [register] itself
/// also subscribes to token-refresh so re-registration after that point is
/// automatic.
class FcmService {
  final IndividualRepository _individualRepository;
  final OrganisationRepository _organisationRepository;
  bool _refreshListenerAttached = false;

  FcmService(this._individualRepository, this._organisationRepository);

  Future<void> register({required bool isOrganisation}) async {
    // Everything here — including just accessing FirebaseMessaging.instance
    // — throws on platforms where Firebase.initializeApp() wasn't
    // configured (this app only ships google-services.json for Android; the
    // Chrome dev target has no Firebase web config). Best-effort: an
    // individual/organisation without push notifications set up yet can
    // still use every other part of the app.
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _send(token, isOrganisation);
      }

      if (!_refreshListenerAttached) {
        _refreshListenerAttached = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          try {
            await _send(newToken, isOrganisation);
          } catch (_) {
            // Best-effort, same as above.
          }
        });
      }
    } catch (_) {
      // Best-effort, see comment above.
    }
  }

  Future<void> _send(String token, bool isOrganisation) {
    return isOrganisation
        ? _organisationRepository.updateFcmToken(token)
        : _individualRepository.updateFcmToken(token);
  }
}
