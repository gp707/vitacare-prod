import { City, DutyType } from '@vitacare/shared-constants';

/** A push as the app receives it: visible text, plus the screen a tap opens.
 *  `route` must be one the app's PushHandler allow-lists for that role. */
export interface PushMessage {
  title: string;
  body: string;
  route: string;
}

/** Screens a push can open, per role. Kept in one place so the server and the
 *  app's allow-list (lib/push/push_handler.dart) are easy to compare. */
export const PushRoutes = {
  caregiverJobs: '/caregiver/jobs',
  caregiverMyJobs: '/caregiver/my-jobs',
  caregiverProfile: '/caregiver/profile',
  individualHome: '/home',
  organisationHome: '/org-home',
} as const;

const CITY_LABELS: Record<string, string> = {
  [City.BANGALORE]: 'Bangalore',
  [City.MUMBAI]: 'Mumbai',
  [City.HYDERABAD]: 'Hyderabad',
  [City.CHENNAI]: 'Chennai',
  [City.PUNE]: 'Pune',
  [City.DELHI]: 'Delhi',
  [City.GURGAON]: 'Gurgaon',
};

export function jobDisplayId(job: {
  admin_job_number?: number | null;
  patient_job_number?: number | null;
}): string {
  if (job.admin_job_number != null) return `ADMIN-JOB-${job.admin_job_number}`;
  if (job.patient_job_number != null) return `PAT-JOB-${job.patient_job_number}`;
  return 'your job';
}

export const organisationJobDisplayId = (requirementNumber: number | null | undefined): string =>
  requirementNumber != null ? `ORG-JOB-${requirementNumber}` : 'your requirement';

const where = (area: string | null | undefined, city: string | null | undefined): string => {
  const cityLabel = city ? (CITY_LABELS[city] ?? city) : '';
  return [area, cityLabel].filter(Boolean).join(', ');
};

// ── Welcome (sent the first time a new account's device registers) ────────

export const welcomeCaregiver = (): PushMessage => ({
  title: 'Registration received',
  body: "Welcome to JustHeal. We'll call you soon to verify your profile.",
  route: PushRoutes.caregiverProfile,
});

export const welcomeIndividual = (): PushMessage => ({
  title: 'Requirement submitted',
  body: "We're reviewing it, usually within a day. We'll notify you when it goes live.",
  route: PushRoutes.individualHome,
});

export const welcomeOrganisation = (): PushMessage => ({
  title: 'Welcome to JustHeal',
  body: 'Post your first requirement to start receiving caregiver applications.',
  route: PushRoutes.organisationHome,
});

// ── Poster (patient / organisation) ───────────────────────────────────────

export const requirementApproved = (displayId: string, route: string): PushMessage => ({
  title: 'Your requirement is live',
  body: `${displayId} was approved. Caregivers can now apply.`,
  route,
});

export const requirementRejected = (displayId: string, reason: string | null | undefined, route: string): PushMessage => ({
  title: 'Requirement not approved',
  body: reason ? `${displayId} was not approved: ${reason}` : `${displayId} was not approved. Please contact support.`,
  route,
});

export const caregiverApplied = (displayId: string, totalApplied: number, route: string): PushMessage => ({
  title: totalApplied > 1 ? `${totalApplied} caregivers applied` : 'A caregiver applied',
  body: `${totalApplied > 1 ? 'Caregivers have' : 'A caregiver has'} applied to ${displayId}. Open the app to review.`,
  route,
});

// ── Caregiver ─────────────────────────────────────────────────────────────

export const applicationAccepted = (displayId: string): PushMessage => ({
  title: "You've been accepted",
  body: `You were accepted for ${displayId}. Contact details are in MyJobs.`,
  route: PushRoutes.caregiverMyJobs,
});

export const applicationDeclined = (displayId: string, reason?: string | null): PushMessage => ({
  title: 'Application update',
  body: reason ? `${displayId}: the employer declined. ${reason}` : `${displayId}: the employer declined your application.`,
  route: PushRoutes.caregiverJobs,
});

// ── Changes to a posting ──────────────────────────────────────────────────

/** A caregiver closed their engagement. A job reopens for new applicants when
 *  that happens; an organisation requirement does not. */
export const caregiverClosedEngagement = (displayId: string, reopened: boolean, route: string): PushMessage => ({
  title: 'A caregiver closed the job',
  body: reopened
    ? `A caregiver closed their engagement on ${displayId}. It is open for new applicants again.`
    : `A caregiver closed their engagement on ${displayId}.`,
  route,
});

/** The employer or admin changed something that matters to applicants. */
export const jobUpdated = (displayId: string, accepted: boolean): PushMessage => ({
  title: 'Job updated',
  body: `${displayId} was updated by the employer. Please check the details.`,
  route: accepted ? PushRoutes.caregiverMyJobs : PushRoutes.caregiverJobs,
});

export const jobCancelled = (displayId: string): PushMessage => ({
  title: 'Job cancelled',
  body: `${displayId} was cancelled by the employer.`,
  route: PushRoutes.caregiverJobs,
});

export const jobNoLongerOpen = (displayId: string): PushMessage => ({
  title: 'Job closed',
  body: `${displayId} is no longer accepting applications.`,
  route: PushRoutes.caregiverJobs,
});

// ── Account status (admin action) ─────────────────────────────────────────

export type BlockLevel = 'job_posting' | 'full';

export const accountBlocked = (level: BlockLevel, route: string): PushMessage =>
  level === 'full'
    ? { title: 'Account blocked', body: 'Your account has been blocked. Please contact support.', route }
    : {
        title: 'Posting paused',
        body: 'Posting new requirements is paused on your account. Please contact support.',
        route,
      };

export const accountUnblocked = (level: BlockLevel, route: string): PushMessage =>
  level === 'full'
    ? { title: 'Account restored', body: 'Your account is active again. You can log in.', route }
    : { title: 'Posting restored', body: 'You can post requirements again.', route };

// ── Nudge ─────────────────────────────────────────────────────────────────

/** Days a live posting waits with no applicants before the poster is nudged. */
export const NO_APPLICANTS_NUDGE_DAYS = 3;

export const noApplicantsYet = (displayId: string, forOrganisation: boolean): PushMessage =>
  forOrganisation
    ? {
        title: 'No applicants yet',
        body: `No caregivers have applied to ${displayId} in ${NO_APPLICANTS_NUDGE_DAYS} days. Consider editing your requirement.`,
        route: PushRoutes.organisationHome,
      }
    : {
        title: 'No applicants yet',
        body: `No caregivers have applied to ${displayId} in ${NO_APPLICANTS_NUDGE_DAYS} days. Try raising the salary or widening your preferences.`,
        route: PushRoutes.individualHome,
      };

// ── Duty-start reminders ──────────────────────────────────────────────────

export type DutyReminderStage = '2d' | '1d' | '12h';

export const dutyReminder = (
  stage: DutyReminderStage,
  job: { display_id: string; area?: string | null; city?: string | null },
): PushMessage => {
  const place = where(job.area, job.city);
  const detail = `${job.display_id}${place ? ` · ${place}` : ''}`;
  switch (stage) {
    case '2d':
      return {
        title: 'Duty in 2 days',
        body: `You need to go to work in 2 days. ${detail}`,
        route: PushRoutes.caregiverMyJobs,
      };
    case '1d':
      return {
        title: 'Duty in 1 day',
        body: `You need to go to work in 1 day. ${detail}`,
        route: PushRoutes.caregiverMyJobs,
      };
    case '12h':
      return {
        title: 'Duty starting soon',
        body: `You need to go on duty soon. Do not forget! ${detail}`,
        route: PushRoutes.caregiverMyJobs,
      };
  }
};

// ── Timing ────────────────────────────────────────────────────────────────

const HOUR_MS = 60 * 60 * 1000;
const IST_OFFSET_MS = 5.5 * HOUR_MS; // India has no daylight saving.

/** When the duty actually begins. Day and live-in shifts start at 08:00 IST,
 *  night shift at 20:00 IST (matches DUTY_TYPE_TIMES in the jobs service).
 *  `startDate` is the job's calendar date, YYYY-MM-DD. */
export function dutyStartAt(startDate: string, dutyType: DutyType | string): Date {
  const hour = dutyType === DutyType.NIGHT_DUTY ? '20' : '08';
  return new Date(`${startDate.slice(0, 10)}T${hour}:00:00+05:30`);
}

/** Which reminder applies for the time left, or null if none is due.
 *  Each band is the "closest" reminder — if a caregiver is accepted late, they
 *  get the one that is true now, not a stale earlier one. */
export function dutyReminderStage(remainingMs: number): DutyReminderStage | null {
  if (remainingMs <= 0) return null; // already started
  if (remainingMs <= 12 * HOUR_MS) return '12h';
  if (remainingMs <= 24 * HOUR_MS) return '1d';
  if (remainingMs <= 48 * HOUR_MS) return '2d';
  return null;
}

/** Sending a stage also uses up every less urgent one, so a caregiver accepted
 *  with 10 hours to go isn't later told "2 days". */
export const stagesUsedBy = (stage: DutyReminderStage): DutyReminderStage[] =>
  stage === '12h' ? ['12h', '1d', '2d'] : stage === '1d' ? ['1d', '2d'] : ['2d'];

const istHour = (d: Date): number => new Date(d.getTime() + IST_OFFSET_MS).getUTCHours();

/** Non-urgent pushes only go out 08:00–21:00 IST. */
export const inSendWindow = (now: Date): boolean => {
  const h = istHour(now);
  return h >= 8 && h < 21;
};

/** The next moment the send window opens (08:00 IST). */
export function nextWindowOpen(now: Date): Date {
  const istNow = new Date(now.getTime() + IST_OFFSET_MS);
  const open = Date.UTC(istNow.getUTCFullYear(), istNow.getUTCMonth(), istNow.getUTCDate(), 8, 0, 0);
  const openUtc = open - IST_OFFSET_MS;
  return new Date(openUtc > now.getTime() ? openUtc : openUtc + 24 * HOUR_MS);
}

/** Whether a reminder should be held back to the next window. The only
 *  exception is the final "go on duty soon" reminder when waiting would mean
 *  it arrives less than an hour before the shift (or after it started). */
export function shouldDefer(now: Date, stage: DutyReminderStage, startAt: Date): boolean {
  if (inSendWindow(now)) return false;
  if (stage !== '12h') return true;
  return nextWindowOpen(now).getTime() < startAt.getTime() - HOUR_MS;
}

// ── What counts as a change worth telling applicants about ────────────────

/** Fields of a job an applicant would want to re-check before going. */
export const JOB_APPLICANT_FIELDS = [
  'city',
  'area',
  'duty_type',
  'start_date',
  'salary_amount',
  'frequency_of_care',
  'care_duration',
] as const;

/** Fields of an organisation requirement an applicant would want to re-check. */
export const REQUIREMENT_APPLICANT_FIELDS = [
  'type_of_nurse',
  'type_of_nurse_other',
  'accommodation_provided',
  'food_provided',
  'special_skills',
  'number_of_vacancies',
  'preferred_gender',
  'experience_required',
  'employment_type',
] as const;

/** True if any of [fields] differs between the two records. Compared as
 *  strings so a database date and a form date of the same day are equal. */
export function changedAny(before: object, after: object, fields: readonly string[]): boolean {
  const norm = (v: unknown) => (v === undefined || v === null ? '' : String(v));
  const a = before as Record<string, unknown>;
  const b = after as Record<string, unknown>;
  return fields.some((f) => norm(a[f]) !== norm(b[f]));
}
