# org.json/Navigation Compose/CameraX/Coil don't need rules — their AARs
# ship their own consumer-rules.pro. androidx.security:security-crypto
# pulls in Google Tink, which references errorprone's annotation classes
# (compile-time-only, SOURCE/CLASS retention, never needed at runtime) —
# R8 can't find them and fails the build unless told they're safe to miss.
-dontwarn com.google.errorprone.annotations.**
