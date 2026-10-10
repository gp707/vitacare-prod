package `in`.vitacasahealth.nativejustheal

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream

/**
 * Mandatory post-registration step, matching the real app's rule that
 * selfie + Aadhaar are both required (uploaded via their own endpoints
 * immediately after /auth/register — see CLAUDE.md's "There is no
 * separate Advanced Details step"). This is the phase-2 replacement for
 * the POC's disabled placeholder cards: real CameraX capture for the
 * selfie (camera-only, no gallery — see "Do NOT use ImageSource.gallery"),
 * a system document picker for Aadhaar (any file type, matching the real
 * app's "Do NOT validate file MIME types" rule).
 */
@Composable
fun DocumentsScreen(onDone: () -> Unit) {
    val context = LocalContext.current
    var selfieFile by remember { mutableStateOf<File?>(null) }
    var aadhaarUri by remember { mutableStateOf<Uri?>(null) }
    var showCamera by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    val aadhaarPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> aadhaarUri = uri }

    if (showCamera) {
        CameraCaptureScreen(
            onCaptured = { file -> selfieFile = file; showCamera = false },
            onCancel = { showCamera = false },
        )
        return
    }

    fun submit() {
        val token = Session.accessToken(context) ?: return
        val selfie = selfieFile
        val aadhaar = aadhaarUri
        if (selfie == null) { errorMessage = "Please take a selfie"; return }
        if (aadhaar == null) { errorMessage = "Please select your Aadhaar document"; return }
        errorMessage = null
        loading = true
        scope.launch {
            val selfieResult = ApiClient.uploadSelfie(token, selfie)
            if (selfieResult is ApiResult.Failure) {
                errorMessage = "Selfie upload failed: ${selfieResult.message}"
                loading = false
                return@launch
            }
            val aadhaarFile = copyUriToCacheFile(context, aadhaar, "aadhaar")
            if (aadhaarFile == null) {
                errorMessage = "Couldn't read the selected Aadhaar file"
                loading = false
                return@launch
            }
            val aadhaarResult = ApiClient.uploadDocument(token, aadhaarFile, DocumentType.AADHAAR)
            loading = false
            when (aadhaarResult) {
                is ApiResult.Success -> onDone()
                is ApiResult.Failure -> errorMessage = "Aadhaar upload failed: ${aadhaarResult.message}"
            }
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Identity Documents", style = MaterialTheme.typography.headlineSmall)
        Text(
            "Both are mandatory — selfie is camera-only, Aadhaar accepts any file type.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp, bottom = 24.dp),
        )

        OutlinedButton(onClick = { showCamera = true }, modifier = Modifier.fillMaxWidth()) {
            Text(if (selfieFile != null) "✓ Selfie captured — retake" else "Take Selfie")
        }
        OutlinedButton(
            onClick = { aadhaarPicker.launch("*/*") },
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
        ) {
            Text(if (aadhaarUri != null) "✓ Aadhaar selected — change" else "Select Aadhaar Document")
        }

        errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 16.dp)) }

        Button(onClick = { submit() }, enabled = !loading, modifier = Modifier.fillMaxWidth().padding(top = 24.dp)) {
            if (loading) CircularProgressIndicator(modifier = Modifier.padding(4.dp)) else Text("Upload & Continue")
        }
        TextButton(onClick = onDone, modifier = Modifier.padding(top = 8.dp)) {
            Text("Skip for now")
        }
    }
}

/** CameraX preview + capture — camera-only, no gallery fallback, matching
 * the Flutter app's own rule exactly. Writes the captured JPEG to the
 * app's cache dir. */
@Composable
private fun CameraCaptureScreen(onCaptured: (File) -> Unit, onCancel: () -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var hasPermission by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        hasPermission = granted
    }
    DisposableEffect(Unit) {
        if (!hasPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
        onDispose {}
    }

    if (!hasPermission) {
        Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text("Camera permission is required to take a selfie.")
            TextButton(onClick = onCancel) { Text("Cancel") }
        }
        return
    }

    val imageCapture = remember { ImageCapture.Builder().build() }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    Column(Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxWidth().aspectRatio(3f / 4f),
            factory = { ctx ->
                val previewView = PreviewView(ctx)
                val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
                cameraProviderFuture.addListener({
                    val cameraProvider = cameraProviderFuture.get()
                    val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
                    // Front camera — a selfie is of the caregiver themselves.
                    val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA
                    try {
                        cameraProvider.unbindAll()
                        cameraProvider.bindToLifecycle(lifecycleOwner, cameraSelector, preview, imageCapture)
                    } catch (e: Exception) {
                        errorMessage = "Couldn't start camera: ${e.message}"
                    }
                }, ContextCompat.getMainExecutor(ctx))
                previewView
            },
        )
        errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(16.dp)) }
        Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Button(
                onClick = {
                    val photoFile = File(context.cacheDir, "selfie_${System.currentTimeMillis()}.jpg")
                    val outputOptions = ImageCapture.OutputFileOptions.Builder(photoFile).build()
                    imageCapture.takePicture(
                        outputOptions,
                        ContextCompat.getMainExecutor(context),
                        object : ImageCapture.OnImageSavedCallback {
                            override fun onImageSaved(output: ImageCapture.OutputFileResults) = onCaptured(photoFile)
                            override fun onError(exception: ImageCaptureException) {
                                errorMessage = "Capture failed: ${exception.message}"
                            }
                        },
                    )
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Capture") }
            TextButton(onClick = onCancel, modifier = Modifier.padding(top = 8.dp)) { Text("Cancel") }
        }
    }
}

/** Aadhaar comes back from the system picker as a content:// Uri, which
 * OkHttp's multipart body can't read directly — copy it into a real cache
 * File first (same reason the Flutter app's own image_picker/file_picker
 * plugins hand back a real file path rather than a raw Uri). */
private fun copyUriToCacheFile(context: android.content.Context, uri: Uri, prefix: String): File? = try {
    val input = context.contentResolver.openInputStream(uri) ?: return null
    val file = File(context.cacheDir, "${prefix}_${System.currentTimeMillis()}")
    FileOutputStream(file).use { output -> input.use { it.copyTo(output) } }
    file
} catch (e: Exception) {
    null
}
