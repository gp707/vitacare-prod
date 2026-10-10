package `in`.vitacasahealth.nativejustheal

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.format.DateTimeParseException

/**
 * Mirrors lib/caregiver/features/jobs/screens/jobs_screen.dart — merged
 * jobs + organisation-requirements browse list, sorted newest-posted-first.
 * Faithfully reproduces the two behaviors added THIS session in the
 * Flutter app (read directly from the current jobs_screen.dart, not from
 * an earlier snapshot): (1) an already-applied listing collapses into a
 * small grey stub UNLESS it's the single most-recently-applied one, which
 * stays full-size with a green border + "You Applied" badge instead of the
 * normal red border. Simplified vs. the Flutter screen: no category/city
 * filter row, no Scope of Work/Rate Card/Duty Requirements buttons, and
 * the application timeline is a single current-status line rather than
 * the full multi-entry history widget — noted here, not silently done.
 */
sealed class Listing {
    abstract val id: String
    abstract val postedAt: String
    abstract val appliedAt: String?

    data class JobListing(val job: JobModel) : Listing() {
        override val id get() = job.id
        override val postedAt get() = job.postedAt
        override val appliedAt get() = job.myApplication?.appliedAtOrNull()
    }

    data class RequirementListing(val requirement: OrganisationRequirementModel) : Listing() {
        override val id get() = requirement.id
        override val postedAt get() = requirement.postedAt
        override val appliedAt get() = requirement.myApplication?.appliedAtOrNull()
    }
}

private fun parseInstant(s: String?): Instant? = s?.let { try { Instant.parse(it) } catch (e: DateTimeParseException) { null } }

/** Mirrors _mostRecentlyAppliedListingId in jobs_screen.dart. */
private fun mostRecentlyAppliedId(listings: List<Listing>): String? =
    listings.mapNotNull { l -> parseInstant(l.appliedAt)?.let { l.id to it } }.maxByOrNull { it.second }?.first

@Composable
fun JobsScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var jobs by remember { mutableStateOf<List<JobModel>>(emptyList()) }
    var requirements by remember { mutableStateOf<List<OrganisationRequirementModel>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val applyingIds = remember { mutableStateOf(setOf<String>()) }
    var reloadTrigger by remember { mutableStateOf(0) }
    var expandedStubId by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        val token = Session.accessToken(context) ?: return
        loading = true
        errorMessage = null
        val jobsResult = ApiClient.getJobs(token)
        val reqResult = ApiClient.getOrganisationRequirements(token)
        when (jobsResult) {
            is ApiResult.Success -> jobs = jobsResult.data
            is ApiResult.Failure -> errorMessage = jobsResult.message
        }
        when (reqResult) {
            is ApiResult.Success -> requirements = reqResult.data
            is ApiResult.Failure -> if (errorMessage == null) errorMessage = reqResult.message
        }
        loading = false
    }

    LaunchedEffect(reloadTrigger) { load() }

    suspend fun applyToJob(job: JobModel, status: String): Boolean {
        val token = Session.accessToken(context) ?: return false
        applyingIds.value = applyingIds.value + job.id
        val result = ApiClient.applyToJob(token, job.id, status)
        applyingIds.value = applyingIds.value - job.id
        return when (result) {
            is ApiResult.Success -> { reloadTrigger++; true }
            is ApiResult.Failure -> { errorMessage = result.message; false }
        }
    }

    suspend fun applyToRequirement(requirement: OrganisationRequirementModel, status: String): Boolean {
        val token = Session.accessToken(context) ?: return false
        applyingIds.value = applyingIds.value + requirement.id
        val result = ApiClient.applyToRequirement(token, requirement.id, status)
        applyingIds.value = applyingIds.value - requirement.id
        return when (result) {
            is ApiResult.Success -> { reloadTrigger++; true }
            is ApiResult.Failure -> { errorMessage = result.message; false }
        }
    }

    val listings = remember(jobs, requirements) {
        (jobs.map { Listing.JobListing(it) } + requirements.map { Listing.RequirementListing(it) })
            .sortedByDescending { parseInstant(it.postedAt) ?: Instant.EPOCH }
    }
    val mostRecentId = remember(listings) { mostRecentlyAppliedId(listings) }

    Column(Modifier.fillMaxSize()) {
        Text(
            "Jobs",
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(16.dp),
        )
        if (loading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        } else {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
                errorMessage?.let { msg ->
                    item { Text(msg, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(bottom = 12.dp)) }
                }
                if (listings.isEmpty()) {
                    item { Text("No jobs posted right now. Pull to refresh not implemented — tap a tab to reload.") }
                }
                items(listings, key = { it.id }) { listing ->
                    val applied = listing.appliedAt != null
                    val collapsed = applied && listing.id != mostRecentId
                    Box(Modifier.padding(bottom = 12.dp)) {
                        if (collapsed) {
                            val displayId = when (listing) {
                                is Listing.JobListing -> jobDisplayId(listing.job)
                                is Listing.RequirementListing -> organisationJobDisplayId(listing.requirement)
                            }
                            AppliedStub(displayId = displayId, onTap = { expandedStubId = listing.id })
                        } else {
                            ListingCard(
                                listing = listing,
                                applied = applied,
                                isApplying = applyingIds.value.contains(listing.id),
                                onApply = {
                                    scope.launch {
                                        when (listing) {
                                            is Listing.JobListing -> applyToJob(listing.job, JobApplicationStatus.APPLIED)
                                            is Listing.RequirementListing -> applyToRequirement(listing.requirement, JobApplicationStatus.APPLIED)
                                        }
                                    }
                                },
                                onReject = if (listing is Listing.JobListing) {
                                    { scope.launch { applyToJob(listing.job, JobApplicationStatus.REJECTED) } }
                                } else null,
                            )
                        }
                    }
                }
            }
        }
    }

    // Tapping a collapsed AppliedStub opens the exact same full card in a
    // dialog — mirrors _showFullJobCard in jobs_screen.dart. Re-looks-up
    // the listing by id each recomposition (not a captured snapshot) so
    // an action taken inside (e.g. withdrawing) is reflected immediately,
    // same "dialog reacts to live state rather than a frozen copy" fix
    // that was needed in the Flutter version this session.
    expandedStubId?.let { id ->
        val listing = listings.firstOrNull { it.id == id }
        if (listing == null) {
            expandedStubId = null
        } else {
            AlertDialog(
                onDismissRequest = { expandedStubId = null },
                confirmButton = {},
                text = {
                    ListingCard(
                        listing = listing,
                        applied = listing.appliedAt != null,
                        isApplying = applyingIds.value.contains(listing.id),
                        onApply = {
                            scope.launch {
                                val ok = when (listing) {
                                    is Listing.JobListing -> applyToJob(listing.job, JobApplicationStatus.APPLIED)
                                    is Listing.RequirementListing -> applyToRequirement(listing.requirement, JobApplicationStatus.APPLIED)
                                }
                                if (ok) expandedStubId = null
                            }
                        },
                        onReject = if (listing is Listing.JobListing) {
                            {
                                scope.launch {
                                    if (applyToJob(listing.job, JobApplicationStatus.REJECTED)) expandedStubId = null
                                }
                            }
                        } else null,
                    )
                },
            )
        }
    }
}

@Composable
private fun ListingCard(
    listing: Listing,
    applied: Boolean,
    isApplying: Boolean,
    onApply: () -> Unit,
    onReject: (() -> Unit)?,
) {
    when (listing) {
        is Listing.JobListing -> JobCard(listing.job, applied, isApplying, onApply, onReject ?: {})
        is Listing.RequirementListing -> RequirementCard(listing.requirement, applied, isApplying, onApply)
    }
}

/** Small solid-green "You Applied" badge — matches the fix just made to
 * the Flutter app's jobs_screen.dart (_AppliedBadge) for the exact same
 * reason: the single still-full-size most-recently-applied card used to
 * look identical to a brand-new unapplied one. */
@Composable
private fun AppliedBadge() {
    Surface(color = Color(0xFF2E7D32), shape = RoundedCornerShape(8.dp)) {
        Row(Modifier.padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Color.White, modifier = Modifier.height(16.dp))
            Text(
                "You Applied — Waiting for Decision",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
                modifier = Modifier.padding(start = 4.dp),
            )
        }
    }
}

/** Collapsed stand-in for an already-applied job/requirement that isn't
 * the most-recently-applied one — mirrors _AppliedStub in jobs_screen.dart
 * (grey, small, diagonal "APPLIED" stamp, tap opens the full card). */
@Composable
private fun AppliedStub(displayId: String, onTap: () -> Unit) {
    Surface(
        onClick = onTap,
        color = Color.Gray.copy(alpha = 0.10f),
        border = BorderStroke(1.5.dp, Color.Gray.copy(alpha = 0.4f)),
        shape = RoundedCornerShape(8.dp),
        modifier = Modifier.fillMaxWidth().height(52.dp),
    ) {
        Box(Modifier.padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
            Text(displayId, color = Color.Gray, fontWeight = FontWeight.Bold)
            Text(
                "APPLIED",
                color = Color.Gray.copy(alpha = 0.55f),
                fontWeight = FontWeight.Black,
                fontSize = 18.sp,
                modifier = Modifier.align(Alignment.Center).rotate(-20f),
            )
        }
    }
}

@Composable
private fun JobCard(job: JobModel, applied: Boolean, isApplying: Boolean, onApply: () -> Unit, onReject: () -> Unit) {
    Surface(
        border = BorderStroke(2.dp, if (applied) Color(0xFF2E7D32) else MaterialTheme.colorScheme.error),
        shape = RoundedCornerShape(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp)) {
            if (applied) {
                AppliedBadge()
                Spacer(Modifier.height(8.dp))
            }
            Text(jobDisplayId(job), fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            Text("${City.displayNames[job.city] ?: job.city}${job.area?.let { " · $it" } ?: ""}")
            Text(DutyType.displayNames[job.dutyType] ?: job.dutyType)
            job.salaryAmount?.let {
                Text("₹$it / ${salaryUnitFor(job.frequencyOfCare)}", fontWeight = FontWeight.Bold, color = Color(0xFF2E7D32))
            }
            if (job.languages.isNotEmpty()) {
                Text("Languages: " + job.languages.joinToString(", ") { Language.displayNames[it] ?: it })
            }
            job.careReceiver?.let { cr ->
                Text(
                    "Patient: ${cr.age}y, ${cr.gender}, ${FeedingType.displayNames[cr.feedingType] ?: cr.feedingType}",
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            job.applicantCount?.let { Text("$it applied", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }

            Spacer(Modifier.height(12.dp))
            when {
                isApplying -> CircularProgressIndicator(modifier = Modifier.height(24.dp))
                job.myApplication != null -> ApplicationStatusLine(job.myApplication, onWithdraw = onReject)
                else -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = onApply, modifier = Modifier.weight(1f), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32))) {
                        Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.height(16.dp))
                        Text(" Apply")
                    }
                    OutlinedButton(onClick = onReject, modifier = Modifier.weight(1f)) {
                        Icon(Icons.Filled.Close, contentDescription = null, modifier = Modifier.height(16.dp))
                        Text(" Reject")
                    }
                }
            }
        }
    }
}

@Composable
private fun RequirementCard(
    requirement: OrganisationRequirementModel,
    applied: Boolean,
    isApplying: Boolean,
    onApply: () -> Unit,
) {
    Surface(
        border = BorderStroke(2.dp, if (applied) Color(0xFF2E7D32) else MaterialTheme.colorScheme.error),
        shape = RoundedCornerShape(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp)) {
            if (applied) {
                AppliedBadge()
                Spacer(Modifier.height(8.dp))
            }
            Text(organisationJobDisplayId(requirement), fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            Text(requirement.organisationName ?: "Organisation", fontWeight = FontWeight.Bold)
            Text(
                listOfNotNull(
                    requirement.organisationType?.let { OrganisationType.displayNames[it] ?: it },
                    requirement.city?.let { City.displayNames[it] ?: it },
                ).joinToString(" · "),
            )
            Text(
                if (requirement.typeOfNurse == "others" && requirement.typeOfNurseOther != null) {
                    requirement.typeOfNurseOther!!
                } else {
                    TypeOfNurse.displayNames[requirement.typeOfNurse] ?: requirement.typeOfNurse
                },
            )
            Text("Vacancies: ${requirement.numberOfVacancies}", fontSize = 13.sp)
            requirement.applicantCount?.let { Text("$it applied", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }

            Spacer(Modifier.height(12.dp))
            when {
                isApplying -> CircularProgressIndicator(modifier = Modifier.height(24.dp))
                requirement.myApplication != null -> ApplicationStatusLine(requirement.myApplication, onWithdraw = null)
                else -> Button(
                    onClick = onApply,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)),
                ) { Text("Apply") }
            }
        }
    }
}

/** Simplified vs. the Flutter app's ApplicationTimeline (one current-status
 * line, not the full newest-first multi-entry history) — see this file's
 * own doc comment for why. */
@Composable
private fun ApplicationStatusLine(application: MyApplicationModel, onWithdraw: (() -> Unit)?) {
    val (label, color) = when (application.status) {
        JobApplicationStatus.APPLIED -> "Applied — waiting for decision" to MaterialTheme.colorScheme.primary
        JobApplicationStatus.ACCEPTED -> "Accepted!" to Color(0xFF2E7D32)
        JobApplicationStatus.COMPLETED -> "Closed" to Color.Gray
        JobApplicationStatus.REJECTED ->
            (if (application.decidedByAdmin) "Declined by employer" else "Declined by you") to MaterialTheme.colorScheme.error
        else -> application.status to Color.Gray
    }
    Column {
        Text(label, color = color, fontWeight = FontWeight.Bold)
        if (application.status == JobApplicationStatus.APPLIED && onWithdraw != null) {
            OutlinedButton(onClick = onWithdraw, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
                Icon(Icons.Filled.Close, contentDescription = null, modifier = Modifier.height(16.dp))
                Text(" Reject Job")
            }
        }
    }
}

private fun salaryUnitFor(frequencyOfCare: String?) = if (frequencyOfCare == FrequencyOfCare.DAILY) "day" else "month"
