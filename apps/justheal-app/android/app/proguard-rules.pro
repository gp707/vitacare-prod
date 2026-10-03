# Project-specific ProGuard/R8 rules, layered on top of Android's own
# proguard-android-optimize.txt (see build.gradle.kts) and whatever
# consumer-rules.pro each plugin's own AAR already bundles (modern Flutter
# plugins — Firebase, image_picker, file_picker, url_launcher,
# connectivity_plus, package_info_plus, shared_preferences — ship their
# own, auto-merged by AGP, so this file starts empty rather than
# pre-emptively blanket-keeping whole packages, which would defeat the
# point of enabling shrinking at all). Add a rule here only if release
# testing (see CLAUDE.md's "App bundle / binary size" notes) turns up an
# actual crash or missing feature traceable to a stripped class.
