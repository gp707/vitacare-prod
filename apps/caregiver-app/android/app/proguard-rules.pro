# Every plugin in this app (firebase_core, firebase_messaging, image_picker,
# file_picker, dio, url_launcher, package_info_plus, connectivity_plus,
# shared_preferences) ships its own consumer ProGuard rules bundled in its
# AAR, which R8 applies automatically — no manual keep rules needed for them.

# Flutter's embedding references Play Core's deferred-components/split-install
# classes even though this app doesn't use deferred components, which makes
# R8 fail with "Missing classes" unless told they're intentionally absent.
-dontwarn com.google.android.play.core.**
