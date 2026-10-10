@file:OptIn(
    androidx.compose.foundation.ExperimentalFoundationApi::class,
    androidx.compose.foundation.layout.ExperimentalLayoutApi::class,
    androidx.compose.material3.ExperimentalMaterial3Api::class,
)

package `in`.vitacasahealth.nativejustheal

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

private data class MandatoryField(
    val isValid: Boolean,
    val bringIntoView: BringIntoViewRequester,
    val focus: FocusRequester? = null,
)

/**
 * Mirrors lib/caregiver/features/registration/screens/registration_screen.dart's
 * mandatory field set and its "always-tappable submit, highlight +
 * scroll/focus to first invalid field" pattern (see CLAUDE.md's
 * "Post a Requirement / Register forms use the same ... pattern" section).
 *
 * Phase 2: selfie/Aadhaar are real now (DocumentsScreen, navigated to on
 * success, mirroring the real app's documents-immediately-after-register
 * flow) — no longer disabled placeholders. Remaining deliberate scope cuts:
 *  - Qualification document / other documents (optional in the real app)
 *    are omitted entirely.
 *  - OTP-mode login-code verification path is omitted — this always uses
 *    the PIN-code path, same as LoginScreen.
 */
@Composable
fun RegistrationScreen(onNavigateToLogin: () -> Unit, onRegistered: () -> Unit) {
    val context = LocalContext.current
    var fullName by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var gender by remember { mutableStateOf(Gender.FEMALE) }
    var age by remember { mutableStateOf("") }
    val languages = remember { mutableStateOf(setOf<String>()) }
    var religion by remember { mutableStateOf<String?>(null) }
    var qualification by remember { mutableStateOf<String?>(null) }
    var termsAccepted by remember { mutableStateOf(false) }

    var showValidationErrors by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    val isFullNameValid = Validators.isValidName(fullName)
    val isPhoneValid = Validators.isValidPhone(phone)
    val isCodeValid = Validators.isValidCode(code)
    val isAgeValid = Validators.isValidAge(age.toIntOrNull())
    val isLanguagesValid = languages.value.isNotEmpty()
    val isReligionValid = religion != null
    val isQualificationValid = qualification != null
    val isTermsValid = termsAccepted

    val canSubmit = isFullNameValid && isPhoneValid && isCodeValid && isAgeValid &&
        isLanguagesValid && isReligionValid && isQualificationValid && isTermsValid

    // One BringIntoViewRequester + (where relevant) FocusRequester per
    // mandatory field, in on-form order — the Compose equivalent of the
    // Flutter screen's GlobalKey + Scrollable.ensureVisible + FocusNode
    // combination.
    val fullNameBringIntoView = remember { BringIntoViewRequester() }
    val fullNameFocus = remember { FocusRequester() }
    val phoneBringIntoView = remember { BringIntoViewRequester() }
    val phoneFocus = remember { FocusRequester() }
    val codeBringIntoView = remember { BringIntoViewRequester() }
    val codeFocus = remember { FocusRequester() }
    val ageBringIntoView = remember { BringIntoViewRequester() }
    val ageFocus = remember { FocusRequester() }
    val languagesBringIntoView = remember { BringIntoViewRequester() }
    val religionBringIntoView = remember { BringIntoViewRequester() }
    val qualificationBringIntoView = remember { BringIntoViewRequester() }
    val termsBringIntoView = remember { BringIntoViewRequester() }

    val mandatoryFieldsInOrder = listOf(
        MandatoryField(isFullNameValid, fullNameBringIntoView, fullNameFocus),
        MandatoryField(isPhoneValid, phoneBringIntoView, phoneFocus),
        MandatoryField(isCodeValid, codeBringIntoView, codeFocus),
        MandatoryField(isAgeValid, ageBringIntoView, ageFocus),
        MandatoryField(isLanguagesValid, languagesBringIntoView),
        MandatoryField(isReligionValid, religionBringIntoView),
        MandatoryField(isQualificationValid, qualificationBringIntoView),
        MandatoryField(isTermsValid, termsBringIntoView),
    )

    fun handleSubmitPressed() {
        if (loading) return
        if (!canSubmit) {
            showValidationErrors = true
            val firstInvalid = mandatoryFieldsInOrder.firstOrNull { !it.isValid }
            if (firstInvalid != null) {
                scope.launch {
                    firstInvalid.bringIntoView.bringIntoView()
                    firstInvalid.focus?.requestFocus()
                }
            }
            return
        }
        errorMessage = null
        loading = true
        scope.launch {
            val result = ApiClient.register(
                phone = "+91$phone",
                fullName = fullName.trim(),
                gender = gender,
                age = age.toInt(),
                languages = languages.value.toList(),
                religion = religion!!,
                highestQualification = qualification!!,
                code = code,
            )
            when (result) {
                is ApiResult.Success -> {
                    Session.save(context, result.data.accessToken)
                    onRegistered()
                }
                is ApiResult.Failure -> errorMessage = result.message
            }
            loading = false
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(24.dp),
    ) {
        item {
            Text(
                "Nurse/Caregivers Registration Form",
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 16.dp),
            )
        }
        item {
            OutlinedTextField(
                value = fullName,
                onValueChange = { fullName = it },
                label = { Text("Full Name (Mandatory)") },
                isError = showValidationErrors && !isFullNameValid,
                supportingText = {
                    if (showValidationErrors && !isFullNameValid) Text("Enter a valid full name (letters and spaces only)")
                },
                modifier = Modifier.fillMaxWidth()
                    .bringIntoViewRequester(fullNameBringIntoView)
                    .focusRequester(fullNameFocus),
            )
        }
        item {
            OutlinedTextField(
                value = phone,
                onValueChange = { if (it.length <= 10) phone = it.filter { c -> c.isDigit() } },
                label = { Text("Phone number (Mandatory)") },
                prefix = { Text("+91 ") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                isError = showValidationErrors && !isPhoneValid,
                supportingText = {
                    if (showValidationErrors && !isPhoneValid) Text("Enter a valid 10-digit mobile number")
                },
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp)
                    .bringIntoViewRequester(phoneBringIntoView)
                    .focusRequester(phoneFocus),
            )
        }
        item {
            OutlinedTextField(
                value = code,
                onValueChange = { if (it.length <= 4) code = it.filter { c -> c.isDigit() } },
                label = { Text("4-Digit Login Code (Mandatory)") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                visualTransformation = PasswordVisualTransformation(),
                isError = showValidationErrors && !isCodeValid,
                supportingText = {
                    Text(
                        if (showValidationErrors && !isCodeValid) "Set a 4-digit code — you'll use it with your phone to log in"
                        else "You'll use this + your phone number to log in from now on",
                    )
                },
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp)
                    .bringIntoViewRequester(codeBringIntoView)
                    .focusRequester(codeFocus),
            )
        }
        item { GenderDropdown(gender, onChange = { gender = it }, modifier = Modifier.padding(top = 16.dp)) }
        item {
            OutlinedTextField(
                value = age,
                onValueChange = { if (it.length <= 3) age = it.filter { c -> c.isDigit() } },
                label = { Text("Age (Mandatory)") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                isError = showValidationErrors && !isAgeValid,
                supportingText = {
                    if (showValidationErrors && !isAgeValid) Text("Age must be between ${Validation.AGE_MIN} and ${Validation.AGE_MAX}")
                },
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp)
                    .bringIntoViewRequester(ageBringIntoView)
                    .focusRequester(ageFocus),
            )
        }
        item {
            Column(modifier = Modifier.padding(top = 16.dp).bringIntoViewRequester(languagesBringIntoView)) {
                Text(
                    "Languages (Mandatory)",
                    fontWeight = FontWeight.SemiBold,
                    color = if (showValidationErrors && !isLanguagesValid) MaterialTheme.colorScheme.error else Color.Unspecified,
                )
                LanguageChips(
                    selected = languages.value,
                    onChange = { languages.value = it },
                    modifier = Modifier.padding(top = 8.dp),
                )
                if (showValidationErrors && !isLanguagesValid) {
                    Text("Select at least one language", color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
                }
            }
        }
        item {
            EnumDropdown(
                label = "Religion (Mandatory)",
                options = Religion.all,
                displayNames = Religion.displayNames,
                selected = religion,
                onChange = { religion = it },
                isError = showValidationErrors && !isReligionValid,
                errorText = "Select your religion",
                modifier = Modifier.padding(top = 16.dp).bringIntoViewRequester(religionBringIntoView),
            )
        }
        item {
            EnumDropdown(
                label = "Highest Qualification (Mandatory)",
                options = Qualification.all,
                displayNames = Qualification.displayNames,
                selected = qualification,
                onChange = { qualification = it },
                isError = showValidationErrors && !isQualificationValid,
                errorText = "Select your highest qualification",
                modifier = Modifier.padding(top = 16.dp).bringIntoViewRequester(qualificationBringIntoView),
            )
        }
        item {
            Column(modifier = Modifier.padding(top = 24.dp)) {
                Text("Documents", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Text(
                    "Selfie and Aadhaar are collected on the next screen, right after registration — same order as the real app.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        item {
            Column(modifier = Modifier.padding(top = 24.dp).bringIntoViewRequester(termsBringIntoView)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = termsAccepted, onCheckedChange = { termsAccepted = it })
                    Text(
                        "I accept the Terms & Conditions (mandatory)",
                        color = if (showValidationErrors && !isTermsValid) MaterialTheme.colorScheme.error else Color.Unspecified,
                    )
                }
                if (showValidationErrors && !isTermsValid) {
                    Text(
                        "You must accept the Terms & Conditions to continue",
                        color = MaterialTheme.colorScheme.error,
                        fontSize = 12.sp,
                        modifier = Modifier.padding(start = 12.dp),
                    )
                }
            }
        }
        item {
            errorMessage?.let {
                Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 16.dp))
            }
        }
        item {
            Button(
                onClick = { handleSubmitPressed() },
                enabled = !loading,
                modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
            ) {
                if (loading) CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Color.White)
                else Text("Register")
            }
        }
        item {
            TextButton(onClick = onNavigateToLogin, modifier = Modifier.padding(top = 8.dp)) {
                Text("Already registered? Login")
            }
        }
    }
}

@Composable
private fun GenderDropdown(selected: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }, modifier = modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = selected.replaceFirstChar { it.uppercase() },
            onValueChange = {},
            readOnly = true,
            label = { Text("Gender") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.menuAnchor(MenuAnchorType.PrimaryNotEditable).fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            Gender.all.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option.replaceFirstChar { c -> c.uppercase() }) },
                    onClick = { onChange(option); expanded = false },
                )
            }
        }
    }
}

@Composable
private fun EnumDropdown(
    label: String,
    options: List<String>,
    displayNames: Map<String, String>,
    selected: String?,
    onChange: (String) -> Unit,
    isError: Boolean,
    errorText: String,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    Column(modifier = modifier.fillMaxWidth()) {
        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }, modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = selected?.let { displayNames[it] ?: it } ?: "",
                onValueChange = {},
                readOnly = true,
                label = { Text(label) },
                isError = isError,
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                modifier = Modifier.menuAnchor(MenuAnchorType.PrimaryNotEditable).fillMaxWidth(),
            )
            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(displayNames[option] ?: option) },
                        onClick = { onChange(option); expanded = false },
                    )
                }
            }
        }
        if (isError) Text(errorText, color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
    }
}

@Composable
private fun LanguageChips(selected: Set<String>, onChange: (Set<String>) -> Unit, modifier: Modifier = Modifier) {
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Language.all.forEach { lang ->
            val isSelected = lang in selected
            FilterChip(
                selected = isSelected,
                onClick = {
                    onChange(if (isSelected) selected - lang else selected + lang)
                },
                label = { Text(Language.displayNames[lang] ?: lang) },
                leadingIcon = if (isSelected) {
                    { Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
                } else null,
            )
        }
    }
}
