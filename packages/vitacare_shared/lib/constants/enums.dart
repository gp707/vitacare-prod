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

class FrequencyOfCare {
  static const daily = 'daily';
  static const monthly = 'monthly';

  static const all = [daily, monthly];

  static const displayNames = {
    daily: 'Daily',
    monthly: 'Monthly',
  };
}

class Communication {
  static const verbal = 'verbal';
  static const difficultyCommunicating = 'difficulty_communicating';
  static const signLanguage = 'sign_language';

  static const all = [verbal, difficultyCommunicating, signLanguage];

  static const displayNames = {
    verbal: 'Can Speak/Communicate',
    difficultyCommunicating: 'Can NOT Speak',
    signLanguage: 'Communicate via Sign Languages',
  };
}

class FeedingType {
  static const oralIndependent = 'oral_independent';
  static const oralNeedsAssistance = 'oral_needs_assistance';
  static const tubeFeeding = 'tube_feeding';
  static const oralAndTube = 'oral_and_tube';

  static const all = [oralIndependent, oralNeedsAssistance, tubeFeeding, oralAndTube];

  static const displayNames = {
    oralIndependent: 'Oral feeding – independent',
    oralNeedsAssistance: 'Oral feeding – needs assistance',
    tubeFeeding: 'Tube feeding',
    oralAndTube: 'Both oral and tube feeding',
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
  static const usesDiapers = 'uses_diapers';
  static const usesBedPan = 'uses_bed_pan';
  static const usesCatheter = 'uses_catheter';
  static const completeAssistance = 'complete_toileting_assistance';
  static const others = 'others';
  static const independent = 'independent';

  static const all = [
    usesDiapers,
    usesBedPan,
    usesCatheter,
    completeAssistance,
    others,
    independent,
  ];

  static const displayNames = {
    usesDiapers: 'Uses diapers',
    usesBedPan: 'Uses bed pan',
    usesCatheter: 'Uses catheter',
    completeAssistance: 'Complete toileting assistance',
    others: 'Others',
    independent: 'Independent',
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
