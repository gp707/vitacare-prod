package `in`.vitacasahealth.nativejustheal

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Work
import androidx.compose.material.icons.filled.Assignment
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController

/**
 * Real navigation graph (phase 2) — replaces the POC's plain
 * mutableStateOf<Screen> swap now that there are enough screens
 * (Login/Register/Jobs/MyJobs/Profile + dialogs) for that to stop scaling.
 * Mirrors the Flutter app's own structure: Login/Register are full-screen,
 * authenticated routes share one 3-tab bottom nav (Profile/Jobs/MyJobs —
 * same order+tab set as CaregiverBottomNav in the real app).
 */
private object Routes {
    const val LOGIN = "login"
    const val REGISTER = "register"
    const val DOCUMENTS = "documents"
    const val JOBS = "jobs"
    const val MY_JOBS = "my_jobs"
    const val PROFILE = "profile"
}

private data class BottomTab(val route: String, val label: String, val icon: @Composable () -> Unit)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            JustHealNativeApp()
        }
    }
}

@Composable
private fun JustHealNativeApp() {
    val context = LocalContext.current
    val navController = rememberNavController()
    val startDestination = if (Session.isLoggedIn(context)) Routes.JOBS else Routes.LOGIN

    MaterialTheme {
        Surface(modifier = Modifier, color = MaterialTheme.colorScheme.background) {
            Column {
                // Pinned above every screen, login included — matches the
                // Flutter app's MaterialApp.builder placement exactly.
                ConnectivityBanner()
                NavHost(
                    navController = navController,
                    startDestination = startDestination,
                    modifier = Modifier.weight(1f),
                ) {
                composable(Routes.LOGIN) {
                    LoginScreen(
                        onNavigateToRegister = { navController.navigate(Routes.REGISTER) },
                        onLoggedIn = {
                            navController.navigate(Routes.JOBS) {
                                popUpTo(Routes.LOGIN) { inclusive = true }
                            }
                        },
                    )
                }
                composable(Routes.REGISTER) {
                    RegistrationScreen(
                        onNavigateToLogin = { navController.popBackStack() },
                        onRegistered = {
                            navController.navigate(Routes.DOCUMENTS) {
                                popUpTo(Routes.LOGIN) { inclusive = true }
                            }
                        },
                    )
                }
                composable(Routes.DOCUMENTS) {
                    DocumentsScreen(
                        onDone = {
                            navController.navigate(Routes.JOBS) {
                                popUpTo(Routes.DOCUMENTS) { inclusive = true }
                            }
                        },
                    )
                }
                composable(Routes.JOBS) {
                    AuthenticatedScaffold(navController) { JobsScreen() }
                }
                composable(Routes.MY_JOBS) {
                    AuthenticatedScaffold(navController) { MyJobsScreen() }
                }
                composable(Routes.PROFILE) {
                    AuthenticatedScaffold(navController) {
                        ProfileScreen(
                            onLoggedOut = {
                                navController.navigate(Routes.LOGIN) {
                                    popUpTo(0) { inclusive = true }
                                }
                            },
                        )
                    }
                }
            }
            }
        }
    }
}

/** The shared 3-tab bottom nav shell every authenticated screen sits in —
 * one Scaffold per destination (not a single persistent one wrapping the
 * whole NavHost) so each tab's own screen-level Scaffold (e.g. for a
 * SnackbarHost) still composes normally; this just supplies the bottom
 * bar + tab-switch navigation consistently. */
@Composable
private fun AuthenticatedScaffold(navController: NavHostController, content: @Composable () -> Unit) {
    val tabs = listOf(
        BottomTab(Routes.PROFILE, "Profile") { Icon(Icons.Filled.Person, contentDescription = null) },
        BottomTab(Routes.JOBS, "Jobs") { Icon(Icons.Filled.Work, contentDescription = null) },
        BottomTab(Routes.MY_JOBS, "MyJobs") { Icon(Icons.Filled.Assignment, contentDescription = null) },
    )
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEach { tab ->
                    NavigationBarItem(
                        selected = backStackEntry?.destination?.hierarchy?.any { it.route == tab.route } == true,
                        onClick = {
                            if (currentRoute != tab.route) {
                                navController.navigate(tab.route) {
                                    popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        },
                        icon = tab.icon,
                        label = { Text(tab.label) },
                    )
                }
            }
        },
    ) { padding ->
        Surface(modifier = Modifier.padding(padding)) {
            content()
        }
    }
}
