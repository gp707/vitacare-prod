plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "in.vitacasahealth.nativejustheal"
    compileSdk = 36

    defaultConfig {
        applicationId = "in.vitacasahealth.native.justheal"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0-poc"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Throwaway self-signed keystore (poc-debug.keystore, generated locally,
    // not committed) — just enough to produce an installable release APK
    // for a real size comparison; not a Play-Store-worthy signing setup.
    signingConfigs {
        create("pocRelease") {
            storeFile = rootProject.file("poc-debug.keystore")
            storePassword = "pocpassword"
            keyAlias = "pocdebug"
            keyPassword = "pocpassword"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("pocRelease")
        }
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")

    // Networking — matches the real Flutter app's own choice of a plain
    // HTTP client + explicit DTOs over a heavier framework for a POC this
    // small (the Flutter app uses Dio; this uses OkHttp directly rather
    // than adding Retrofit/Moshi on top for just 2 endpoints).
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.json:json:20240303")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // Phase 2 — full caregiver flow additions.
    implementation("androidx.navigation:navigation-compose:2.8.5")
    // Plain SharedPreferences-backed session storage is enough here — the
    // Flutter app itself just persists the raw JWT via SharedPreferences on
    // Android too (flutter_secure_storage would be the real-app-parity
    // choice; EncryptedSharedPreferences is the native equivalent, added
    // only if session storage specifically needs scrutiny later).
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    // CameraX — selfie capture is camera-only, matching the Flutter app's
    // own "Do NOT use ImageSource.gallery" rule.
    implementation("androidx.camera:camera-core:1.4.1")
    implementation("androidx.camera:camera-camera2:1.4.1")
    implementation("androidx.camera:camera-lifecycle:1.4.1")
    implementation("androidx.camera:camera-view:1.4.1")
    // Document picker (Aadhaar/qualification/other docs) — SAF, no extra
    // dependency needed (ActivityResultContracts.GetContent is in
    // activity-compose already).
    implementation("io.coil-kt:coil-compose:2.7.0")
    // Real FCM wiring (firebase-messaging + google-services.json) is
    // deliberately deferred — the existing Firebase project only registers
    // the real app's package names (in.vitacasahealth.justheal /
    // caregiver_app), and adding this POC's distinct applicationId
    // requires Firebase Console access this task doesn't have and
    // shouldn't touch on a shared production project unprompted. The
    // PUT /caregiver/fcm-token call itself is still wired (ApiClient /
    // ProfileRepository) using a locally-generated placeholder token, so
    // the request shape is proven even though no real push can be
    // received — see FcmPlaceholder.kt.
}
