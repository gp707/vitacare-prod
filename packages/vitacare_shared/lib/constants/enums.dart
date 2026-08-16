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
  static const active = 'active';
  static const closed = 'closed';

  static const all = [active, closed];
}

class JobApplicationStatus {
  static const applied = 'applied';
  static const rejected = 'rejected';
  static const accepted = 'accepted';

  static const all = [applied, rejected, accepted];
}

class Gender {
  static const male = 'male';
  static const female = 'female';
  static const other = 'other';

  static const all = [male, female, other];
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
  static const other = 'other';

  static const all = [dayDuty, nightDuty, liveIn, other];

  static const displayNames = {
    dayDuty: 'Day Duty',
    nightDuty: 'Night Duty',
    liveIn: 'Live-In',
    other: 'Other',
  };
}

class Mobility {
  static const walksIndependently = 'walks_independently';
  static const walksWithAssistance = 'walks_with_assistance';
  static const usesWalker = 'uses_walker';
  static const usesWheelchair = 'uses_wheelchair';
  static const bedridden = 'bedridden';

  static const all = [
    walksIndependently,
    walksWithAssistance,
    usesWalker,
    usesWheelchair,
    bedridden,
  ];

  static const displayNames = {
    walksIndependently: 'Walks independently',
    walksWithAssistance: 'Walks with assistance',
    usesWalker: 'Uses walker',
    usesWheelchair: 'Uses wheelchair',
    bedridden: 'Bedridden',
  };
}

class Communication {
  static const verbal = 'verbal';
  static const difficultyCommunicating = 'difficulty_communicating';
  static const signLanguage = 'sign_language';
  static const otherNonVerbal = 'other_non_verbal';

  static const all = [verbal, difficultyCommunicating, signLanguage, otherNonVerbal];

  static const displayNames = {
    verbal: 'Speaks / communicates verbally',
    difficultyCommunicating: 'Has difficulty communicating',
    signLanguage: 'Sign language',
    otherNonVerbal: 'Other / non-verbal communication',
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

class MedicalAssistance {
  static const medicationReminders = 'medication_reminders';
  static const medicationAdministration = 'medication_administration';
  static const insulinAdministration = 'insulin_administration';
  static const otherInjections = 'other_injections';
  static const other = 'other';

  static const all = [
    medicationReminders,
    medicationAdministration,
    insulinAdministration,
    otherInjections,
    other,
  ];

  static const displayNames = {
    medicationReminders: 'Medication reminders',
    medicationAdministration: 'Medication administration',
    insulinAdministration: 'Insulin administration',
    otherInjections: 'Other injections',
    other: 'Other',
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
  ];
}

class UserRole {
  static const superAdmin = 'super_admin';
  static const admin = 'admin';
  static const caregiver = 'caregiver';

  static const all = [superAdmin, admin, caregiver];
}

class DocumentType {
  static const qualification = 'qualification';
  static const aadhaar = 'aadhaar';
  static const other = 'other';

  static const all = [qualification, aadhaar, other];
}
