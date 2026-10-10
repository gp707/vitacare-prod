package `in`.vitacasahealth.nativejustheal

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Mirrors lib/caregiver/features/profile/screens/profile_view_screen.dart —
 * identity display, Delete My Account (PIN re-auth, irreversible — see
 * CLAUDE.md's "Account Deletion" section), Logout. Simplified vs. the
 * Flutter screen: no self-edit form (age/languages/qualification/
 * preferred-cities editing), no document re-upload, no phone/PIN change —
 * read-only profile display only, explicitly cut for scope here. Rate
 * Card / Scope of Work / Duty Requirements are reachable as buttons on
 * this screen rather than a persistent AppBar icon on every screen (the
 * real app's own placement) — this POC has no shared AppBar component yet.
 */
@Composable
fun ProfileScreen(onLoggedOut: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var profile by remember { mutableStateOf<CaregiverProfileModel?>(null) }
    var loading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showDeleteDialog by remember { mutableStateOf(false) }
    var showRateCard by remember { mutableStateOf(false) }
    var showScopeOfWork by remember { mutableStateOf(false) }
    var showDutyRequirements by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        val token = Session.accessToken(context) ?: return@LaunchedEffect
        when (val result = ApiClient.getProfile(token)) {
            is ApiResult.Success -> {
                profile = result.data
                Session.saveProfileId(context, result.data.profileId)
                // Best-effort — a real push token needs real Firebase app
                // registration (see build.gradle.kts's own note on why
                // that's deferred); this still proves the request shape.
                ApiClient.updateFcmToken(token, "poc-placeholder-${UUID.randomUUID()}")
            }
            is ApiResult.Failure -> errorMessage = result.message
        }
        loading = false
    }

    fun logout() {
        Session.logout(context)
        onLoggedOut()
    }

    if (showDeleteDialog) {
        DeleteAccountDialog(
            onDismiss = { showDeleteDialog = false },
            onDeleted = { logout() },
        )
    }
    if (showRateCard) InfoDialog("Rate Card", onDismiss = { showRateCard = false }) { RateCardContent() }
    if (showScopeOfWork) InfoDialog("Scope of Work", onDismiss = { showScopeOfWork = false }) { ScopeOfWorkContent() }
    if (showDutyRequirements) InfoDialog("Duty Requirements", onDismiss = { showDutyRequirements = false }) { DutyRequirementsContent() }

    if (loading) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp)) {
        Text("Profile", style = MaterialTheme.typography.headlineSmall)
        errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp)) }

        profile?.let { p ->
            Spacer(Modifier.height(16.dp))
            caregiverDisplayId(p)?.let { Text(it, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary) }
            Text(p.fullName, style = MaterialTheme.typography.titleLarge)
            Text(p.phone, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(16.dp))
            ProfileRow("Gender", p.gender.replaceFirstChar { it.uppercase() })
            ProfileRow("Age", p.age.toString())
            ProfileRow("Languages", p.languages.joinToString(", ") { Language.displayNames[it] ?: it })
            p.religion?.let { ProfileRow("Religion", Religion.displayNames[it] ?: it) }
            p.highestQualification?.let { ProfileRow("Qualification", Qualification.displayNames[it] ?: it) }
            ProfileRow("Status", verificationStatusLabel(p.verificationStatus))
        }

        Spacer(Modifier.height(24.dp))
        Divider()
        Spacer(Modifier.height(16.dp))
        Text("Guidance", fontWeight = FontWeight.Bold)
        OutlinedButton(onClick = { showRateCard = true }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) { Text("Rate Card") }
        OutlinedButton(onClick = { showScopeOfWork = true }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) { Text("Scope of Work") }
        OutlinedButton(onClick = { showDutyRequirements = true }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) { Text("Duty Requirements") }

        Spacer(Modifier.height(24.dp))
        Divider()
        Spacer(Modifier.height(16.dp))
        TextButton(onClick = { logout() }, modifier = Modifier.fillMaxWidth()) { Text("Logout") }
        TextButton(
            onClick = { showDeleteDialog = true },
            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurfaceVariant),
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Delete My Account") }
    }
}

@Composable
private fun ProfileRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Text(label, modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        Text(value, modifier = Modifier.weight(2f), fontWeight = FontWeight.Bold)
    }
}

private fun verificationStatusLabel(status: String) = when (status) {
    VerificationStatus.PENDING_CALL -> "Pending Call"
    VerificationStatus.AVAILABLE -> "Available"
    VerificationStatus.UNAVAILABLE -> "Unavailable"
    VerificationStatus.ASSIGNED -> "Assigned"
    VerificationStatus.REJECTED -> "Rejected"
    else -> status
}

/** Mirrors showDeleteAccountDialog() — re-enters the PIN before an
 * irreversible delete (the one re-auth step in this product's self-service
 * flows), retries inline on a wrong PIN rather than closing. */
@Composable
private fun DeleteAccountDialog(onDismiss: () -> Unit, onDeleted: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Delete My Account") },
        text = {
            Column {
                Text(
                    "This permanently deletes your account and anonymizes your data. This cannot be undone. " +
                        "Enter your 4-digit PIN to confirm.",
                    color = MaterialTheme.colorScheme.error,
                    fontSize = 13.sp,
                )
                OutlinedTextField(
                    value = code,
                    onValueChange = { if (it.length <= 4) code = it.filter { c -> c.isDigit() } },
                    label = { Text("4-digit PIN") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                )
                errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp)) }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !loading,
                onClick = {
                    if (!Validators.isValidCode(code)) {
                        errorMessage = "Enter the 4-digit PIN"
                        return@TextButton
                    }
                    val token = Session.accessToken(context) ?: return@TextButton
                    loading = true
                    scope.launch {
                        when (val result = ApiClient.deleteAccount(token, code)) {
                            is ApiResult.Success -> onDeleted()
                            is ApiResult.Failure -> { errorMessage = result.message; loading = false }
                        }
                    }
                },
            ) {
                if (loading) CircularProgressIndicator(modifier = Modifier.height(20.dp)) else Text("Delete", color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun InfoDialog(title: String, onDismiss: () -> Unit, content: @Composable () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) { content() } },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}

@Composable
private fun RateCardContent() {
    var cards by remember { mutableStateOf<List<RateCardModel>?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        when (val result = ApiClient.getRateCard()) {
            is ApiResult.Success -> cards = result.data
            is ApiResult.Failure -> errorMessage = result.message
        }
    }
    when {
        errorMessage != null -> Text(errorMessage!!, color = MaterialTheme.colorScheme.error)
        cards == null -> CircularProgressIndicator()
        else -> cards!!.forEach { card ->
            Text(card.title, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
            card.columnLabels.forEachIndexed { i, label ->
                val cell = card.cells.firstOrNull()?.getOrNull(i) ?: ""
                Text("$label: $cell", fontSize = 13.sp, modifier = Modifier.padding(top = 2.dp))
            }
        }
    }
}

@Composable
private fun ScopeOfWorkContent() {
    var model by remember { mutableStateOf<ScopeOfWorkModel?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        when (val result = ApiClient.getScopeOfWork()) {
            is ApiResult.Success -> model = result.data
            is ApiResult.Failure -> errorMessage = result.message
        }
    }
    when {
        errorMessage != null -> Text(errorMessage!!, color = MaterialTheme.colorScheme.error)
        model == null -> CircularProgressIndicator()
        else -> listOf(
            CareTier.COMPANION_CARE to model!!.companionCare,
            CareTier.BEDSIDE_CARE to model!!.bedsideCare,
            CareTier.CRITICAL_CARE to model!!.criticalCare,
        ).forEach { (tier, bullets) ->
            Text(CareTier.displayNames[tier] ?: tier, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
            bullets.forEach { Text("• $it", fontSize = 13.sp) }
        }
    }
}

@Composable
private fun DutyRequirementsContent() {
    var model by remember { mutableStateOf<DutyRequirementsModel?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        when (val result = ApiClient.getDutyRequirements()) {
            is ApiResult.Success -> model = result.data
            is ApiResult.Failure -> errorMessage = result.message
        }
    }
    when {
        errorMessage != null -> Text(errorMessage!!, color = MaterialTheme.colorScheme.error)
        model == null -> CircularProgressIndicator()
        else -> listOf(
            DutyType.LIVE_IN to model!!.liveIn,
            DutyType.DAY_DUTY to model!!.dayDuty,
            DutyType.NIGHT_DUTY to model!!.nightDuty,
        ).forEach { (duty, bullets) ->
            Text(DutyType.displayNames[duty] ?: duty, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
            bullets.forEach { Text("• $it", fontSize = 13.sp) }
        }
    }
}
