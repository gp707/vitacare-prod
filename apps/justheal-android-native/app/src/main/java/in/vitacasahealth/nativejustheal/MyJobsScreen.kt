package `in`.vitacasahealth.nativejustheal

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.format.DateTimeParseException

/**
 * Mirrors lib/caregiver/features/jobs/screens/my_assignment_screen.dart —
 * every job/requirement the caregiver currently holds an accepted or
 * completed application for (GET .../assigned, sorted oldest-decision-
 * first per CLAUDE.md's "Job/Application Flow"), each with its own "Mark
 * Complete" button once accepted/active. A caregiver can hold more than
 * one at once — both lists are arrays, not a single job/null. Simplified
 * vs. the Flutter screen: no full ApplicationTimeline history widget (see
 * JobsScreen.kt's own doc comment for the same cut).
 */
@Composable
fun MyJobsScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var jobs by remember { mutableStateOf<List<JobModel>>(emptyList()) }
    var requirements by remember { mutableStateOf<List<OrganisationRequirementModel>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val completingIds = remember { mutableStateOf(setOf<String>()) }
    var reloadTrigger by remember { mutableStateOf(0) }

    suspend fun load() {
        val token = Session.accessToken(context) ?: return
        loading = true
        errorMessage = null
        when (val jobsResult = ApiClient.getAssignedJobs(token)) {
            is ApiResult.Success -> jobs = jobsResult.data
            is ApiResult.Failure -> errorMessage = jobsResult.message
        }
        when (val reqResult = ApiClient.getAssignedOrganisationRequirements(token)) {
            is ApiResult.Success -> requirements = reqResult.data
            is ApiResult.Failure -> if (errorMessage == null) errorMessage = reqResult.message
        }
        loading = false
    }

    LaunchedEffect(reloadTrigger) { load() }

    fun completeJob(id: String) {
        scope.launch {
            val token = Session.accessToken(context) ?: return@launch
            completingIds.value = completingIds.value + id
            val result = ApiClient.completeJob(token, id)
            completingIds.value = completingIds.value - id
            when (result) {
                is ApiResult.Success -> reloadTrigger++
                is ApiResult.Failure -> errorMessage = result.message
            }
        }
    }

    fun completeRequirement(id: String) {
        scope.launch {
            val token = Session.accessToken(context) ?: return@launch
            completingIds.value = completingIds.value + id
            val result = ApiClient.completeRequirement(token, id)
            completingIds.value = completingIds.value - id
            when (result) {
                is ApiResult.Success -> reloadTrigger++
                is ApiResult.Failure -> errorMessage = result.message
            }
        }
    }

    Column(Modifier.fillMaxSize()) {
        Text("MyJobs", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(16.dp))
        if (loading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else if (jobs.isEmpty() && requirements.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("No active jobs yet — apply to one from the Jobs tab.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
                errorMessage?.let { msg -> item { Text(msg, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(bottom = 12.dp)) } }
                items(jobs, key = { "job_${it.id}" }) { job ->
                    AssignedJobCard(
                        job = job,
                        isCompleting = completingIds.value.contains(job.id),
                        onMarkComplete = { completeJob(job.id) },
                    )
                    Spacer(Modifier.height(12.dp))
                }
                items(requirements, key = { "req_${it.id}" }) { req ->
                    AssignedRequirementCard(
                        requirement = req,
                        isCompleting = completingIds.value.contains(req.id),
                        onMarkComplete = { completeRequirement(req.id) },
                    )
                    Spacer(Modifier.height(12.dp))
                }
            }
        }
    }
}

@Composable
private fun AssignedJobCard(job: JobModel, isCompleting: Boolean, onMarkComplete: () -> Unit) {
    val status = job.myApplication?.status
    Surface(
        border = BorderStroke(2.dp, if (status == JobApplicationStatus.COMPLETED) Color.Gray else Color(0xFF2E7D32)),
        shape = RoundedCornerShape(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(jobDisplayId(job), fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            Text("${City.displayNames[job.city] ?: job.city}${job.area?.let { " · $it" } ?: ""}")
            Text(DutyType.displayNames[job.dutyType] ?: job.dutyType)
            job.jobPoster?.let { poster ->
                Text(
                    "Contact: ${poster.fullName} — ${poster.phone}",
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            Spacer(Modifier.height(8.dp))
            when (status) {
                JobApplicationStatus.COMPLETED -> Text("Closed — work completed", color = Color.Gray, fontSize = 13.sp)
                else -> Button(onClick = onMarkComplete, enabled = !isCompleting, modifier = Modifier.fillMaxWidth()) {
                    if (isCompleting) CircularProgressIndicator(modifier = Modifier.height(20.dp)) else Text("Mark Complete")
                }
            }
        }
    }
}

@Composable
private fun AssignedRequirementCard(requirement: OrganisationRequirementModel, isCompleting: Boolean, onMarkComplete: () -> Unit) {
    val status = requirement.myApplication?.status
    Surface(
        border = BorderStroke(2.dp, if (status == JobApplicationStatus.COMPLETED) Color.Gray else Color(0xFF2E7D32)),
        shape = RoundedCornerShape(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(organisationJobDisplayId(requirement), fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            Text(requirement.organisationName ?: "Organisation", fontWeight = FontWeight.Bold)
            requirement.organisationPhone?.let {
                Text("Contact: $it", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 4.dp))
            }
            Spacer(Modifier.height(8.dp))
            when (status) {
                JobApplicationStatus.COMPLETED -> Text("Closed — work completed", color = Color.Gray, fontSize = 13.sp)
                else -> Button(onClick = onMarkComplete, enabled = !isCompleting, modifier = Modifier.fillMaxWidth()) {
                    if (isCompleting) CircularProgressIndicator(modifier = Modifier.height(20.dp)) else Text("Mark Complete")
                }
            }
        }
    }
}
