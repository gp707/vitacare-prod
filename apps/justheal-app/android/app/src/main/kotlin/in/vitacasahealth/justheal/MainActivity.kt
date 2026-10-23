package `in`.vitacasahealth.justheal

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Draw behind the status/navigation bars on every Android version.
        // Android 15+ (we target 36) enforces this anyway; opting in
        // explicitly makes Android 14 and older look and behave the same
        // (Play's "edge-to-edge may not display for all users" warning).
        // Flutter's Scaffold/AppBar/SafeArea apply the system-bar insets.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }
}
