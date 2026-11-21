import 'package:vitacare_shared/vitacare_shared.dart';

/// The Play Store page of the app. Android is the only store for now.
const String playStorePackage = 'in.vitacasahealth.justheal';

/// Who is sharing — decides the wording of the invite.
enum ShareAudience { caregiver, individual, organisation }

/// The plain Play Store link: just the app's id, no tracking parameters, so it stays as short
/// as the Play Store allows and looks clean in a chat.
const String appStoreLink = 'https://play.google.com/store/apps/details?id=$playStorePackage';

/// The message for "tell a friend about JustHeal". Plain text, English, no names,
/// phone numbers or any job or patient detail.
String appInviteMessage(ShareAudience audience) {
  const link = appStoreLink;
  switch (audience) {
    case ShareAudience.caregiver:
      return 'Looking for nursing or caregiver jobs? JustHeal connects caregivers with patients and families '
          'who need them. Download the app and register: $link';
    case ShareAudience.individual:
      return 'Need a nurse or caregiver for someone at home? JustHeal helps families find caregivers quickly. '
          'Download the app: $link';
    case ShareAudience.organisation:
      return 'Hiring nurses or caregivers for your hospital, clinic or rehab? Post your requirement on JustHeal '
          'and get applications from caregivers. Download the app: $link';
  }
}

/// The message for "share this job" (caregivers). Only what the job listing itself already
/// shows every caregiver in a city and shift, and the salary when it is a plain number —
/// never an address, name or phone number.
String jobShareMessage(JobModel job) {
  final duty = DutyType.displayNames[job.dutyType] ?? job.dutyType;
  final city = City.displayNames[job.city] ?? job.city;
  final salary = job.salaryAmount;
  final plainSalary = salary != null && RegExp(r'^\d{1,7}$').hasMatch(salary.trim());
  final unit = job.frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month';
  final pay = plainSalary ? ', ₹${formatRupees(int.parse(salary.trim()))} per $unit' : '';
  return 'Nursing job on JustHeal: $duty in $city$pay. Download the app and apply: $appStoreLink';
}
