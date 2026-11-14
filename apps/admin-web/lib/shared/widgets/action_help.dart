import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Hover (desktop) / long-press (touch) explanation for an admin action
/// button: what it does, who it affects and whether it can be undone.
class ActionHelp extends StatelessWidget {
  final String message;
  final Widget child;

  const ActionHelp({super.key, required this.message, required this.child});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 12),
      preferBelow: false,
      padding: const EdgeInsets.all(AppSpacing.sm),
      margin: const EdgeInsets.all(AppSpacing.sm),
      constraints: const BoxConstraints(maxWidth: 340),
      textAlign: TextAlign.left,
      textStyle:
          const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
      child: child,
    );
  }
}

/// The wording for every button on a Jobs-tab row. One place, so a job row
/// and an organisation row say the same thing for the same action.
class JobActionHelp {
  static const applicants = 'Opens the list of caregivers who applied.\n'
      'From there you can open a caregiver\'s profile, accept one, or reject one. '
      'Accepting closes the job to new applicants and marks that caregiver as working; '
      'rejecting an accepted caregiver reopens the job.\n'
      'Nothing changes until you pick someone.';

  static const downloadReport = 'Download a PDF of the jobs listed below, with the same filters and search.\n'
      'It has location, salary and patient condition for each job. It does not include internal notes, '
      'the patient\'s name, or the poster\'s name and phone, so it is safe to share.';

  static const notes = 'View, add or edit your internal note.\n'
      'Only admins see it. It is never shown to the poster or to caregivers.';

  static const notesOrganisation =
      'View, add or edit your internal note about this organisation.\n'
      'It is the organisation\'s own note, so it is the same on all its jobs and on its Rehab/Hospitals page. '
      'Only admins see it.';

  static const remind =
      'Sends a push notification right now to every caregiver who can apply '
      '("APPLY NOW BEFORE IT\'S FILLED"), respecting the job\'s preferred gender.\n'
      'It goes to many people at once and cannot be taken back, so use it only when you really want more applicants. '
      'Only available while the job is active.';

  static const remindRequirement =
      'Sends a push notification right now to every caregiver who can apply, '
      'saying a hospital/rehab in this area is hiring.\n'
      'It goes to many people at once and cannot be taken back. Only available while it is active.';

  static const close =
      'Stops new applications and hides the job from caregivers. No confirmation is asked.\n'
      'Caregivers who applied but were not accepted get a "no longer accepting" notification. '
      'An already accepted caregiver stays accepted.\n'
      'To open it again, use Edit and save.';

  static const movePendingReview =
      'Takes the job off caregivers\' Jobs list until you approve it again.\n'
      'Existing applications are kept. Use it when something needs fixing before it is shown.';

  static const approve =
      'Makes it live immediately and sends a "new job" notification to every caregiver who can apply.\n'
      'Check the details first. Once sent, the notification cannot be recalled.';

  static const reject =
      'Declines this posting so it never goes live. You will be asked for a reason, '
      'which the poster can see, and they are notified.\n'
      'Only for postings waiting for review.';

  static String edit({required bool pendingReview, required bool closed}) {
    if (pendingReview) {
      return 'Opens the full form to change any detail.\n'
          'Saving a posting that is waiting for review also APPROVES it: it goes live and every caregiver who can apply is notified.';
    }
    if (closed) {
      return 'Opens the full form to change any detail.\n'
          'Saving a closed job REOPENS it: it goes live again and every caregiver who can apply is notified.';
    }
    return 'Opens the full form to change any detail.\n'
        'The job stays live and no new-job notification is sent. '
        'If you change the place, shift, start date or pay, caregivers who applied are told.';
  }

  static String editRequirement(
      {required bool pendingReview, required bool closed}) {
    if (pendingReview) {
      return 'Opens the form to correct any detail the organisation entered.\n'
          'Saving a posting that is waiting for review also APPROVES it: it goes live and caregivers are notified.';
    }
    if (closed) {
      return 'Opens the form to change any detail.\n'
          'Saving a closed requirement REOPENS it and caregivers are notified.';
    }
    return 'Opens the form to change any detail.\n'
        'It stays live. Caregivers who applied are told if a key detail changes.';
  }
}

/// Hover help for every other admin screen (accounts, tickets, errors,
/// settings, push). Same rule as [JobActionHelp]: say what happens, who it
/// reaches, and whether it can be undone.
class AdminHelp {
  // ── Caregiver detail ──
  static const caregiverApprove =
      'Marks this caregiver as verified and available for work. Do this after the verification call and document check.\n'
      'They are notified and can be accepted onto jobs. You can change the status again later.';
  static const caregiverReject =
      'Rejects this caregiver. You will be asked for a reason, which the caregiver sees, and they are notified.\n'
      'They can fix their profile and any edit sends them back to "pending call" for review automatically.';
  static const setStatus =
      'Admin override: sets the caregiver to the chosen status from any current status, skipping the normal rules.\n'
      'It only changes the status. Setting "assigned" does not attach a job, and setting "available" does not close an accepted job. '
      'The change is recorded in the audit log.';
  static const addOtherDocument =
      'Uploads an extra document for this caregiver (max 10 MB). It is added to their profile and kept in the document history.';
  static const viewDownload = 'Opens the current file in a new tab so you can view or save it. Nothing is changed.';
  static const documentHistory =
      'Shows every earlier version of this document with the upload date. Old versions are kept until you delete them.';
  static const deleteVersion =
      'Permanently deletes this one older uploaded file from storage.\n'
      'This cannot be undone. The caregiver\'s current version of the document cannot be deleted from here.';

  // ── Individual / organisation / caregiver account ──
  static const resetPin =
      'Sets a new 4-digit login PIN that you type. The old PIN is not needed and stops working at once.\n'
      'Verify the person by phone first, then tell them the new PIN yourself. The change is recorded in the audit log.';
  static const viewJobsPosted = 'Opens the Jobs tab filtered to this account\'s postings. Nothing is changed.';
  static const blockPosting =
      'Stops this account from posting NEW jobs. You will be asked for a reason and they are notified.\n'
      'Jobs already posted, their applicants and their login keep working.';
  static const unblockPosting = 'Lets this account post jobs again, and notifies them.';
  static const blockProfile =
      'Locks this account out completely: they cannot log in or use the app. You will be asked for a reason and they are told first.\n'
      'Use "Unblock" to restore access. Use "Block Posting" instead if you only want to stop new postings.';
  static const unblockProfile = 'Restores login for this account, and notifies them.';
  static const editProfile =
      'Makes the name, phone and other details editable. Nothing is saved until you press Save Changes.';
  static const saveChanges =
      'Saves only what you changed and records it in the audit log.\n'
      'Changing the phone number keeps the same account, with all its jobs and applications. '
      'It must not already belong to another account.';
  static const editNotes = 'Makes the internal note editable. Only admins see it.';
  static const saveNotes = 'Saves the internal note. Only admins see it; never the account holder or caregivers.';
  static const viewFullAuditLog = 'Opens the Audit Logs screen filtered to this account, with every recorded action.';

  // ── Admin management ──
  static const createAdmin = 'Creates a new admin account who can log in to this portal. They cannot manage other admins unless made Super Admin.';
  static const makeSuperAdmin =
      'Gives this admin full access, including creating, deactivating and deleting other admins and changing system settings.\n'
      'Only do this for someone you fully trust.';
  static const deactivateAdmin =
      'Blocks this admin from logging in. Their past actions stay in the audit log.\n'
      'Reversible: use Activate to let them in again.';
  static const activateAdmin = 'Lets this admin log in again.';
  static const deleteAdmin =
      'Permanently removes this admin account.\n'
      'Their past actions stay in the audit log. This cannot be undone; use Deactivate if you may need them back.';

  // ── Tickets ──
  static const resolveTicket =
      'Marks this "Forgot PIN" request as handled. It does NOT reset the PIN.\n'
      'First verify the person by phone and reset the PIN on their account page (open it from the name), then resolve the ticket.';

  // ── Error logs ──
  static const resolveError =
      'Marks this one error as handled. The customer is not notified. Use it once you have fixed the problem or called them.';
  static const viewErrors = 'Shows every error this person hit. Nothing is changed.';
  static const markContacted =
      'Marks ALL of this person\'s open errors as resolved in one step ("I called them"). You can add a note.\n'
      'The customer is not notified.';
  static const callPhone = 'Starts a phone call to this number from your device.';
  static const whatsappPhone = 'Opens a WhatsApp chat with this number. Nothing is sent until you press send.';

  // ── Push notifications ──
  static const clearSelection = 'Empties your selection of recipients. Nothing is sent and no one is notified.';
  static const notifySelected =
      'Opens the message composer for everyone you selected. Nothing is sent until you press Send or Schedule there.';
  static const cancelPush =
      'Cancels this scheduled notification so it is never sent.\n'
      'Only works while it is still pending, and cannot be undone.';

  // ── Settings ──
  static const saveMaintenance =
      'Applies right now. If Maintenance mode is on, EVERY user of the app (caregivers, patients and organisations) is blocked and sees the message above until you turn it off.\n'
      'Use it only for planned downtime.';
  static const editMinVersion =
      'Sets the oldest app version allowed for this platform. Anyone on an older version sees a full-screen "Update required" and cannot use the app until they update.\n'
      'Make sure the new version is live in the store first.';
  static const saveMinVersion =
      'Saves and applies immediately. Users below this version are blocked on their next app launch.';
  static const saveApplyByWindow =
      'Saves the number of days used as the suggested "Posted more than N days ago" filter on the Jobs tab. It does not change or close any job.';
  static const saveAuditRetention =
      'Sets how many days of audit history are kept. Entries older than this are DELETED automatically and cannot be recovered.\n'
      'Do not shorten it unless you are sure.';
  static const changePassword = 'Changes the password of the account you are logged in with. Use a strong password you have not used elsewhere.';
  static const saveRateCard =
      'Saves this salary guidance. Patients/families and caregivers see the new figures the next time they open the Rate Card.';
  static const saveScopeOfWork =
      'Saves the scope-of-work text. Caregivers, patients and admins see the new wording straight away for every job of that care level.';
  static const saveDutyRequirements =
      'Saves what patients/families must arrange for each shift. Patients see the new text the next time they open it.';
  static const addBullet = 'Adds an empty line to this list. It is not saved until you press Save.';
  static const removeBullet = 'Removes this line from the list. It is not saved until you press Save.';

  // ── In-app messages ──
  static const saveMessage = 'Saves this message. If it is enabled, users see it in their in-app messages the next time it applies.';
  static const deleteMessage = 'Permanently deletes this message so users no longer see it. This cannot be undone; you can disable it instead.';

  // ── Reports ──
  static const runReport = 'Runs the report for the filters chosen. Read-only: nothing is changed or sent.';
}
