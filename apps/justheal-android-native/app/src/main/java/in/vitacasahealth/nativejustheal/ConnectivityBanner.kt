package `in`.vitacasahealth.nativejustheal

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * Mirrors lib/patient_hospital/core/connectivity/connectivity_banner.dart
 * (shared across the Flutter app despite living in the patient_hospital
 * tree) — the real lesson from that file carries over directly: a network
 * *interface* being up (Wi-Fi/cellular connected) does NOT mean the
 * backend is actually reachable (DNS can be broken while the interface
 * itself reports fine). So this does the same two-layer check: an
 * interface-down (no network at all) callback turns the banner on
 * INSTANTLY and can never clear it by itself; actually clearing the
 * banner always goes through a real reachability probe (a cheap request
 * to the public GET /rate-card endpoint — any HTTP response, even an
 * error status, counts as "reachable"; only a connection/DNS/timeout
 * failure counts as offline), run once on mount, every 15s, and
 * immediately whenever the interface reconnects.
 */
private val probeClient = OkHttpClient.Builder()
    .connectTimeout(5, TimeUnit.SECONDS)
    .readTimeout(5, TimeUnit.SECONDS)
    .build()

private suspend fun probeReachable(): Boolean = withContext(Dispatchers.IO) {
    try {
        val request = Request.Builder().url("https://api.vitacasahealth.in/v1/rate-card").get().build()
        probeClient.newCall(request).execute().use { true } // any HTTP response at all = reachable
    } catch (e: Exception) {
        false
    }
}

@Composable
fun ConnectivityBanner() {
    val context = LocalContext.current
    var interfaceUp by remember { mutableStateOf(isInterfaceUp(context)) }
    var offline by remember { mutableStateOf(!interfaceUp) }
    var probeTrigger by remember { mutableStateOf(0) }

    DisposableEffect(Unit) {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                interfaceUp = true
                probeTrigger++ // interface reconnected — re-probe immediately, don't wait for the 15s tick
            }
            override fun onLost(network: Network) {
                interfaceUp = isInterfaceUp(context)
                if (!interfaceUp) offline = true // instant, never clears the banner by itself
            }
        }
        connectivityManager.registerNetworkCallback(NetworkRequest.Builder().build(), callback)
        onDispose { connectivityManager.unregisterNetworkCallback(callback) }
    }

    LaunchedEffect(Unit) {
        while (true) {
            if (interfaceUp) offline = !probeReachable()
            delay(15_000)
        }
    }
    LaunchedEffect(probeTrigger) {
        if (probeTrigger > 0 && interfaceUp) offline = !probeReachable()
    }

    if (offline) {
        Surface(color = MaterialTheme.colorScheme.error, modifier = Modifier.fillMaxWidth()) {
            Text(
                "You're offline. Some actions may not work.",
                color = Color.White,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
            )
        }
    }
}

private fun isInterfaceUp(context: Context): Boolean {
    val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    val network = connectivityManager.activeNetwork ?: return false
    val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
    return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
}
