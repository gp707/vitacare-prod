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

class JobResponseType {
  static const accepted = 'accepted';
  static const rejected = 'rejected';
  static const moreDetails = 'more_details';

  static const all = [accepted, rejected, moreDetails];
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

class ServiceMode {
  static const twentyFourHrsLiveIn = '24hrs_live_in';
  static const twelveHrsPg = '12hrs_pg';

  static const all = [twentyFourHrsLiveIn, twelveHrsPg];

  static const displayNames = {
    twentyFourHrsLiveIn: '24Hrs (Live-In)',
    twelveHrsPg: '12Hrs (Nearby PG)',
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

class WorkType {
  static const companionCare = 'companion_care';
  static const bedsideCare = 'bedside_care';
  static const criticalCare = 'critical_care';

  static const all = [companionCare, bedsideCare, criticalCare];

  static const displayNames = {
    companionCare: 'Companion Care',
    bedsideCare: 'Bedside Care (includes diaper change)',
    criticalCare: 'Critical Care',
  };
}

class SalaryRanges {
  static const companionCare = (min: 25000, max: 30000);
  static const bedsideCare = (min: 28000, max: 35000);
  static const criticalCare = (min: 30000, max: 45000);
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
