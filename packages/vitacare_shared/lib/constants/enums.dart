class VerificationStatus {
  static const pendingCall = 'pending_call';
  static const available = 'available'; // Verified & available (green icon)
  static const unavailable = 'unavailable'; // Verified but not available (toggled off)
  static const assigned = 'assigned'; // Currently assigned to work
  static const rejected = 'rejected';

  static const all = [
    pendingCall,
    available,
    unavailable,
    assigned,
    rejected,
  ];
}

class JobStatus {
  // A NurseNow individual-posted job sits here until an admin approves
  // (-> active) or rejects (-> closed) it. Admin's own postings skip this
  // entirely — created straight into active.
  static const pendingReview = 'pending_review';
  static const active = 'active';
  static const closed = 'closed';

  static const all = [pendingReview, active, closed];
  static const displayNames = {
    pendingReview: 'Pending Review',
    active: 'Active',
    closed: 'Closed',
  };
}

class AppPlatform {
  static const android = 'android';
  static const ios = 'ios';

  static const all = [android, ios];
}

class JobApplicationStatus {
  static const applied = 'applied';
  static const rejected = 'rejected';
  static const accepted = 'accepted';
  static const completed = 'completed';

  static const all = [applied, rejected, accepted, completed];
}

class Gender {
  static const male = 'male';
  static const female = 'female';
  static const other = 'other';

  static const all = [male, female, other];
  static const displayNames = {male: 'Male', female: 'Female', other: 'Other'};
}

class Language {
  static const hindi = 'hindi';
  static const english = 'english';
  static const kannada = 'kannada';
  static const tamil = 'tamil';
  static const telugu = 'telugu';
  static const malayalam = 'malayalam';
  static const bengali = 'bengali';
  static const gujarati = 'gujarati';
  static const marathi = 'marathi';

  static const all = [
    hindi,
    english,
    kannada,
    tamil,
    telugu,
    malayalam,
    bengali,
    gujarati,
    marathi,
  ];

  static const displayNames = {
    hindi: 'Hindi',
    english: 'English',
    kannada: 'Kannada',
    tamil: 'Tamil',
    telugu: 'Telugu',
    malayalam: 'Malayalam',
    bengali: 'Bengali',
    gujarati: 'Gujarati',
    marathi: 'Marathi',
  };
}

class Religion {
  static const hindu = 'hindu';
  static const muslim = 'muslim';
  static const christian = 'christian';
  static const others = 'others';

  static const all = [hindu, muslim, christian, others];

  static const displayNames = {
    hindu: 'Hindu',
    muslim: 'Muslim',
    christian: 'Christian',
    others: 'Others',
  };
}

class DutyType {
  static const dayDuty = 'day_duty';
  static const nightDuty = 'night_duty';
  static const liveIn = 'live_in';

  static const all = [liveIn, dayDuty, nightDuty];

  static const displayNames = {
    liveIn: '24Hrs - Live In',
    dayDuty: '12Hrs Day Shift (8am to 8pm)',
    nightDuty: '12Hrs Night Shift (8pm to 8am)',
  };
}

/// When an admin-editable individual_messages row is shown on NurseNow's
/// Messages tab — picked by admin per message, evaluated client-side
/// against the individual's own already-fetched requirement data (see
/// resolveMessages() in apps/nursenow-app/lib/features/individual/data/
/// requirement_messages.dart).
class MessageEvent {
  static const welcome = 'welcome';
  static const requirementLive = 'requirement_live';
  static const requirementCareTier = 'requirement_care_tier';
  // Evaluated against the account's most recently posted requirement's
  // applications (any status present on it, regardless of the
  // requirement's own status — acceptance closes the requirement, so
  // caregiverAccepted/caregiverClosed can never coincide with a still-
  // "live" requirement). Not mutually exclusive with each other or with
  // requirementLive/requirementCareTier — e.g. a still-live requirement
  // can simultaneously have other applied-but-undecided candidates.
  static const caregiverApplied = 'caregiver_applied';
  static const caregiverAccepted = 'caregiver_accepted';
  static const caregiverRejected = 'caregiver_rejected';
  static const caregiverClosed = 'caregiver_closed';

  static const all = [
    welcome,
    requirementLive,
    requirementCareTier,
    caregiverApplied,
    caregiverAccepted,
    caregiverRejected,
    caregiverClosed,
  ];

  static const displayNames = {
    welcome: 'Welcome (before any requirement ever posted)',
    requirementLive: 'Requirement is live',
    requirementCareTier: 'Requirement is live + has a care tier (supports {tier})',
    caregiverApplied: 'A caregiver applied (most recent requirement)',
    caregiverAccepted: 'A caregiver was accepted (most recent requirement)',
    caregiverRejected: 'A caregiver was rejected (most recent requirement)',
    caregiverClosed: 'A caregiver closed the engagement (most recent requirement)',
  };
}

/// A curated, bounded set of icon keys an admin can pick per message —
/// never free text, so a bad value can't crash the client. Keys match
/// their corresponding Flutter Icons.* constant name.
class MessageIcon {
  static const editNote = 'edit_note';
  static const rule = 'rule';
  static const travelExplore = 'travel_explore';
  static const wavingHand = 'waving_hand';
  static const rocketLaunch = 'rocket_launch';
  static const favorite = 'favorite';
  static const medicalServices = 'medical_services';
  static const emergency = 'emergency';
  static const info = 'info';
  static const celebration = 'celebration';
  static const personAdd = 'person_add';
  static const checkCircle = 'check_circle';
  static const cancel = 'cancel';
  static const taskAlt = 'task_alt';

  static const all = [
    editNote,
    rule,
    travelExplore,
    wavingHand,
    rocketLaunch,
    favorite,
    medicalServices,
    emergency,
    info,
    celebration,
    personAdd,
    checkCircle,
    cancel,
    taskAlt,
  ];
}

class FrequencyOfCare {
  static const daily = 'daily';
  static const monthly = 'monthly';

  static const all = [daily, monthly];

  static const displayNames = {
    daily: 'Daily',
    monthly: 'Monthly',
  };
}

/// How long the engagement is expected to last — collected on NurseNow
/// individual postings only; nullable on a job since admin-posted jobs and
/// pre-existing rows never set it.
class CareDuration {
  static const fewDays = 'few_days';
  static const fewWeeks = 'few_weeks';
  static const fewMonths = 'few_months';
  static const longTerm = 'long_term';

  static const all = [fewDays, fewWeeks, fewMonths, longTerm];

  static const displayNames = {
    fewDays: 'Need for few Days',
    fewWeeks: 'Need for Few Weeks',
    fewMonths: 'Need for Minimum a Month',
    longTerm: 'Need for Long Term',
  };
}

class FeedingType {
  static const oralFeeding = 'oral_feeding';
  static const tubeFeeding = 'tube_feeding';
  static const others = 'others';

  static const all = [oralFeeding, tubeFeeding, others];

  static const displayNames = {
    oralFeeding: 'Oral feeding',
    tubeFeeding: 'Tube feeding',
    others: 'Others (Cannula etc.)',
  };
}

class MedicalCondition {
  static const cancer = 'cancer';
  static const stroke = 'stroke';
  static const brainInjury = 'brain_injury';
  static const dementiaAlzheimers = 'dementia_alzheimers';
  static const parkinsons = 'parkinsons';
  static const heartCondition = 'heart_condition';
  static const kidneyDiseaseDialysis = 'kidney_disease_dialysis';
  static const diabetes = 'diabetes';
  static const colostomy = 'colostomy';
  static const paralysis = 'paralysis';
  static const tb = 'tb';
  static const bp = 'bp';
  static const oxygenSupport = 'oxygen_support';
  static const insulinAdministrationSupport = 'insulin_administration_support';
  static const injectionSupport = 'injection_support';
  static const cannulaCare = 'cannula_care';
  static const catheterCare = 'catheter_care';
  static const nebulisationSupport = 'nebulisation_support';
  static const other = 'other';

  static const all = [
    cancer,
    stroke,
    brainInjury,
    dementiaAlzheimers,
    parkinsons,
    heartCondition,
    kidneyDiseaseDialysis,
    diabetes,
    colostomy,
    paralysis,
    tb,
    bp,
    oxygenSupport,
    insulinAdministrationSupport,
    injectionSupport,
    cannulaCare,
    catheterCare,
    nebulisationSupport,
    other,
  ];

  static const displayNames = {
    cancer: 'Cancer',
    stroke: 'Stroke',
    brainInjury: 'Brain injury',
    dementiaAlzheimers: "Dementia / Alzheimer's",
    parkinsons: "Parkinson's",
    heartCondition: 'Heart condition / Cardiac condition',
    kidneyDiseaseDialysis: 'Kidney disease / Dialysis',
    diabetes: 'Diabetes',
    colostomy: 'Colostomy',
    paralysis: 'Paralysis',
    tb: 'TB',
    bp: 'BP',
    oxygenSupport: 'Oxygen support',
    insulinAdministrationSupport: 'Insulin administration support',
    injectionSupport: 'Injection support',
    cannulaCare: 'Cannula care',
    catheterCare: 'Catheter care',
    nebulisationSupport: 'Nebulisation support',
    other: 'Other',
  };
}

class ToiletAssistance {
  static const independent = 'independent';
  static const diapersBedsideSupport = 'diapers_bedside_support';
  static const usesCatheter = 'uses_catheter';
  static const others = 'others';

  static const all = [independent, diapersBedsideSupport, usesCatheter, others];

  static const displayNames = {
    independent: 'Independent/minimal support',
    diapersBedsideSupport: 'Diapers/bedside support',
    usesCatheter: 'Catheter support',
    others: 'Others',
  };
}

class VitalMonitoringType {
  static const bloodPressure = 'blood_pressure';
  static const bloodSugar = 'blood_sugar';
  static const oxygenSpo2 = 'oxygen_spo2';
  static const temperature = 'temperature';
  static const pulse = 'pulse';
  static const other = 'other';

  static const all = [bloodPressure, bloodSugar, oxygenSpo2, temperature, pulse, other];

  static const displayNames = {
    bloodPressure: 'Blood pressure',
    bloodSugar: 'Blood sugar',
    oxygenSpo2: 'Oxygen / SpO₂',
    temperature: 'Temperature',
    pulse: 'Pulse',
    other: 'Other',
  };
}

class City {
  static const bangalore = 'bangalore';
  static const mumbai = 'mumbai';
  static const hyderabad = 'hyderabad';
  static const chennai = 'chennai';
  static const pune = 'pune';
  static const delhi = 'delhi';
  static const gurgaon = 'gurgaon';

  static const all = [bangalore, mumbai, hyderabad, chennai, pune, delhi, gurgaon];

  static const displayNames = {
    bangalore: 'Bangalore',
    mumbai: 'Mumbai',
    hyderabad: 'Hyderabad',
    chennai: 'Chennai',
    pune: 'Pune',
    delhi: 'Delhi',
    gurgaon: 'Gurgaon',
  };
}

class Qualification {
  static const rnAbove2Years = 'rn_above_2_years';
  static const rnBelow2Years = 'rn_below_2_years';
  static const registeredRecently = 'registered_recently';
  static const bscGnmUnregistered = 'bsc_gnm_unregistered';
  static const anmStudentBacklog = 'anm_student_backlog';
  static const gdaNonNursing = 'gda_non_nursing';

  static const all = [
    rnAbove2Years,
    rnBelow2Years,
    registeredRecently,
    bscGnmUnregistered,
    anmStudentBacklog,
    gdaNonNursing,
  ];

  static const displayNames = {
    rnAbove2Years: 'Registered Nurse above 2 years of experience',
    rnBelow2Years: 'Registered Nurse below 2 years experience',
    registeredRecently: 'Registered Recently',
    bscGnmUnregistered: 'BSC / GNM Completed - Unregistered',
    anmStudentBacklog: 'ANM/Nursing Student/ Backlog',
    gdaNonNursing: 'GDA / Non Nursing',
  };
}

class AuditAction {
  static const registration = 'registration';
  static const login = 'login';
  static const profileUpdated = 'profile_updated';
  static const statusChanged = 'status_changed';
  static const codeChanged = 'code_changed';
  static const adminEditProfile = 'admin_edit_profile';
  static const adminNoteAdded = 'admin_note_added';
  static const adminCreated = 'admin_created';
  static const adminDeactivated = 'admin_deactivated';
  static const phoneChanged = 'phone_changed';
  static const editsAcknowledged = 'edits_acknowledged';
  static const jobPosted = 'job_posted';
  static const jobClosed = 'job_closed';
  static const jobResponse = 'job_response';
  static const jobApplicationDecided = 'job_application_decided';
  static const adminDocumentUploaded = 'admin_document_uploaded';
  static const adminRoleChanged = 'admin_role_changed';
  static const adminActivated = 'admin_activated';
  static const jobReminderSent = 'job_reminder_sent';
  static const jobUpdated = 'job_updated';
  static const jobCompleted = 'job_completed';
  static const jobReapplied = 'job_reapplied';
  static const orgRequirementPosted = 'org_requirement_posted';
  static const orgRequirementUpdated = 'org_requirement_updated';
  static const orgRequirementRejected = 'org_requirement_rejected';
  static const orgRequirementApplicationDecided = 'org_requirement_application_decided';
  static const rateCardUpdated = 'rate_card_updated';
  static const scopeOfWorkUpdated = 'scope_of_work_updated';
  static const dutyRequirementsUpdated = 'duty_requirements_updated';
  static const jobSettingsUpdated = 'job_settings_updated';
  static const adminPasswordChanged = 'admin_password_changed';
  static const individualMessageCreated = 'individual_message_created';
  static const individualMessageUpdated = 'individual_message_updated';
  static const individualMessageDeleted = 'individual_message_deleted';

  static const all = [
    registration,
    login,
    profileUpdated,
    statusChanged,
    codeChanged,
    adminEditProfile,
    adminNoteAdded,
    adminCreated,
    adminDeactivated,
    phoneChanged,
    editsAcknowledged,
    jobPosted,
    jobClosed,
    jobResponse,
    jobApplicationDecided,
    adminDocumentUploaded,
    adminRoleChanged,
    adminActivated,
    jobReminderSent,
    jobUpdated,
    jobCompleted,
    jobReapplied,
    orgRequirementPosted,
    orgRequirementUpdated,
    orgRequirementRejected,
    orgRequirementApplicationDecided,
    rateCardUpdated,
    scopeOfWorkUpdated,
    dutyRequirementsUpdated,
    jobSettingsUpdated,
    adminPasswordChanged,
    individualMessageCreated,
    individualMessageUpdated,
    individualMessageDeleted,
  ];
}

class UserRole {
  static const superAdmin = 'super_admin';
  static const admin = 'admin';
  static const caregiver = 'caregiver';
  // NurseNow patient/family account.
  static const individual = 'individual';
  // NurseNow hospital/rehab/clinic account.
  static const organisation = 'organisation';

  static const all = [superAdmin, admin, caregiver, individual, organisation];
}

class OrganisationType {
  static const hospital = 'hospital';
  static const rehab = 'rehab';
  static const clinic = 'clinic';

  static const all = [hospital, rehab, clinic];
  static const displayNames = {
    hospital: 'Hospital',
    rehab: 'Rehab',
    clinic: 'Clinic',
  };
}

/// Distinct from Qualification (a caregiver's own self-reported credential)
/// — this is the category an organisation requests when posting a
/// requirement. Replaced wholesale (2026-08-19) with the hospital-facing
/// category list actually used by admin — validated at the DTO layer
/// (@IsIn) on the backend, not a DB CHECK, so this can change without a
/// migration.
class TypeOfNurse {
  static const registeredNurse = 'registered_nurse';
  static const nursingCompleted = 'nursing_completed';
  static const nursingStudent = 'nursing_student';
  static const auxiliaryNurse = 'auxiliary_nurse';
  static const nonNursingStaff = 'non_nursing_staff';
  static const paramedicalStaff = 'paramedical_staff';
  static const others = 'others';

  static const all = [
    registeredNurse,
    nursingCompleted,
    nursingStudent,
    auxiliaryNurse,
    nonNursingStaff,
    paramedicalStaff,
    others,
  ];

  static const displayNames = {
    registeredNurse: 'Registered Nurse',
    nursingCompleted: 'Nursing Completed Nurse',
    nursingStudent: 'Nursing Student',
    auxiliaryNurse: 'Auxiliary Nurse',
    nonNursingStaff: 'Non Nursing Staff',
    paramedicalStaff: 'Paramedical Staff',
    others: 'Others',
  };
}

/// Organisation requirement scheduling — admin picks exactly one mode on
/// approval, replacing the old daily-only single start_date. Deliberately
/// organisation-only; regular jobs (admin/individual postings) keep their
/// existing single start_date field unchanged.
class ScheduleType {
  static const dateRange = 'date_range';
  static const specificDays = 'specific_days';

  static const all = [dateRange, specificDays];

  static const displayNames = {
    dateRange: 'Date Range',
    specificDays: 'Specific Days',
  };
}

/// Only meaningful when scheduleType is ScheduleType.specificDays — picks
/// whether specificDays holds ISO weekday numbers (1=Monday..7=Sunday,
/// recurring every week) or day-of-month numbers (1-31, recurring every
/// month).
class ScheduleRepeat {
  static const weekly = 'weekly';
  static const monthly = 'monthly';

  static const all = [weekly, monthly];

  static const displayNames = {
    weekly: 'Weekly',
    monthly: 'Monthly',
  };

  /// 1-indexed (Monday=1..Sunday=7), matching Dart's DateTime.weekday.
  static const weekdayAbbreviations = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };
}

/// Which app is calling POST /auth/login/code — phone is unique per app
/// bucket, not globally: NURSEJOBS -> role=caregiver only, NURSENOW ->
/// role IN (individual, organisation).
class LoginApp {
  static const nursejobs = 'nursejobs';
  static const nursenow = 'nursenow';
}

// Scopes an OTP send/verify to what it's proving — a register OTP can never
// be replayed to satisfy a login, and vice versa.
class OtpPurpose {
  static const register = 'register';
  static const login = 'login';
}

/// organisation_profiles.city is validated against City.all plus this one
/// extra sentinel — a separate org-scoped list, not an extension of the
/// shared City enum.
const organisationCityOthers = 'others';

class DocumentType {
  static const qualification = 'qualification';
  static const aadhaar = 'aadhaar';
  static const other = 'other';

  static const all = [qualification, aadhaar, other];
}
