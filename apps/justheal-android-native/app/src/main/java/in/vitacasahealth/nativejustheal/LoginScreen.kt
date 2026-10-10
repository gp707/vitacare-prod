package `in`.vitacasahealth.nativejustheal

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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

/**
 * Mirrors lib/caregiver/features/auth/screens/login_screen.dart's PIN-mode
 * path only (OTP mode, LoginApp routing to nursenow, etc. are the same
 * screen in Flutter via otpModeProvider — out of scope here too; this
 * hardcodes PIN mode / app=nursejobs like the real caregiver flow does by
 * default). Phase 2 adds real session persistence (Session.save) and
 * navigation on success — the POC phase deliberately stopped short of
 * both to keep scope to "does the network call work at all".
 */
@Composable
fun LoginScreen(onNavigateToRegister: () -> Unit, onLoggedIn: () -> Unit) {
    val context = LocalContext.current
    var phone by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun submit() {
        if (!Validators.isValidPhone(phone)) {
            errorMessage = "Enter a valid 10-digit mobile number"
            return
        }
        if (!Validators.isValidCode(code)) {
            errorMessage = "Enter the 4-digit code"
            return
        }
        errorMessage = null
        loading = true
        scope.launch {
            when (val result = ApiClient.loginCode("+91$phone", code)) {
                is ApiResult.Success -> {
                    Session.save(context, result.data.accessToken)
                    onLoggedIn()
                }
                is ApiResult.Failure -> errorMessage = result.message
            }
            loading = false
        }
    }

    // Forgot PIN — a small inline dialog, same "creates a support ticket,
    // show whatever message comes back" behavior as the Flutter app's
    // ForgotPinDialog, pre-filled from whatever's already typed above.
    var showForgotPin by remember { mutableStateOf(false) }
    if (showForgotPin) {
        ForgotPinDialog(initialPhone = phone, onDismiss = { showForgotPin = false })
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(PaddingValues(24.dp)),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("JustHeal", fontSize = 32.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
        Text("Native Android POC", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Column(modifier = Modifier.padding(top = 32.dp).fillMaxWidth()) {
            OutlinedTextField(
                value = phone,
                onValueChange = { if (it.length <= 10) phone = it.filter { c -> c.isDigit() } },
                label = { Text("Phone number") },
                prefix = { Text("+91 ") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = code,
                onValueChange = { if (it.length <= 4) code = it.filter { c -> c.isDigit() } },
                label = { Text("4-digit code") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
            )
            errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp)) }
            TextButton(onClick = { showForgotPin = true }, modifier = Modifier.padding(top = 4.dp)) {
                Text("Forgot PIN?")
            }
            Button(
                onClick = { submit() },
                enabled = !loading,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            ) {
                if (loading) CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Color.White)
                else Text("Login")
            }
            TextButton(onClick = onNavigateToRegister, modifier = Modifier.padding(top = 24.dp)) {
                Text("New here? Register")
            }
        }
    }
}
