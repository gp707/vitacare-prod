import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/features/individual/data/requirement_messages.dart';

JobModel _requirement({
  String id = 'job-1',
  String status = 'active',
  Map<String, dynamic>? careReceiver,
}) {
  return JobModel.fromJson({
    'id': id,
    'patient_job_number': 542,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'start_date': '2026-09-01',
    'languages': ['hindi'],
    'salary_amount': '1800',
    'status': status,
    'posted_by': 'individual-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    if (careReceiver != null) 'care_receiver': careReceiver,
  });
}

Map<String, dynamic> _careReceiverJson({
  List<String> toiletAssistance = const ['independent'],
  String feedingType = 'oral_feeding',
}) =>
    {
      'id': 'cr-1',
      'age': 74,
      'gender': 'female',
      'weight_kg': 58,
      'feeding_type': feedingType,
      'has_medical_condition': false,
      'medical_conditions': [],
      'toilet_assistance': toiletAssistance,
      'requires_vital_monitoring': false,
      'vital_monitoring_types': [],
    };

JobApplicationModel _application({
  String id = 'app-1',
  String jobId = 'job-1',
  String status = 'applied',
}) =>
    JobApplicationModel(
      id: id,
      jobId: jobId,
      profileId: 'profile-1',
      status: status,
      fullName: 'Test Caregiver',
      phone: '+919876543210',
      updatedAt: '2026-08-01T10:00:00Z',
    );

IndividualMessageModel _template({
  required String id,
  required String event,
  String icon = MessageIcon.info,
  required String message,
  required int displayOrder,
}) =>
    IndividualMessageModel(
      id: id,
      event: event,
      icon: icon,
      message: message,
      displayOrder: displayOrder,
      enabled: true,
    );

/// Mirrors the real migration seed content (6 messages), so these tests
/// double as a regression check that resolveMessages() reproduces the
/// exact behavior the old hardcoded functions had.
List<IndividualMessageModel> _seedTemplates() => [
      _template(
        id: 'm1',
        event: MessageEvent.requirementLive,
        icon: MessageIcon.editNote,
        message: 'You can edit this job and change salary.',
        displayOrder: 10,
      ),
      _template(
        id: 'm2',
        event: MessageEvent.requirementCareTier,
        icon: MessageIcon.favorite,
        message: "Based on the patient's condition we see you need {tier}.",
        displayOrder: 20,
      ),
      _template(
        id: 'm3',
        event: MessageEvent.requirementLive,
        icon: MessageIcon.rule,
        message: 'You can post one requirement at a time.',
        displayOrder: 30,
      ),
      _template(
        id: 'm4',
        event: MessageEvent.requirementLive,
        icon: MessageIcon.travelExplore,
        message: 'If you are not getting applicants, consider widening your scope.',
        displayOrder: 40,
      ),
      _template(
        id: 'm5',
        event: MessageEvent.welcome,
        icon: MessageIcon.wavingHand,
        message: 'Welcome to NurseNow!',
        displayOrder: 10,
      ),
      _template(
        id: 'm6',
        event: MessageEvent.welcome,
        icon: MessageIcon.rocketLaunch,
        message: 'Ready to get started? Post a Requirement.',
        displayOrder: 20,
      ),
    ];

Iterable<String> _texts(List<MessageItem> messages) => messages.map((m) => m.text);

void main() {
  group('resolveMessages — live requirement', () {
    test('returns nothing for a closed requirement with no applications', () {
      expect(resolveMessages(_seedTemplates(), [_requirement(status: 'closed')], const []), isEmpty);
    });

    test('includes the edit/salary tip for a pending_review requirement', () {
      final messages = resolveMessages(_seedTemplates(), [_requirement(status: 'pending_review')], const []);
      expect(_texts(messages), contains(contains('You can edit this job and change salary')));
    });

    test('includes the edit/salary tip for an active requirement', () {
      final messages = resolveMessages(_seedTemplates(), [_requirement(status: 'active')], const []);
      expect(_texts(messages), contains(contains('You can edit this job and change salary')));
    });

    test('includes the one-requirement-at-a-time tip while live', () {
      final messages = resolveMessages(_seedTemplates(), [_requirement(status: 'active')], const []);
      expect(_texts(messages), contains(contains('You can post one requirement at a time')));
    });

    test('includes the widen-your-scope tip while live', () {
      final messages = resolveMessages(_seedTemplates(), [_requirement(status: 'active')], const []);
      expect(_texts(messages), contains(contains('consider widening your scope')));
    });

    test('omits the derived-tier tip when there is no care_receiver yet', () {
      final messages = resolveMessages(_seedTemplates(), [_requirement(status: 'pending_review')], const []);
      expect(messages.any((m) => m.text.contains('we see you need')), isFalse);
    });

    test('interpolates {tier} as Companion Care for an independent/oral-feeding patient', () {
      final messages = resolveMessages(
        _seedTemplates(),
        [_requirement(status: 'active', careReceiver: _careReceiverJson())],
        const [],
      );
      expect(_texts(messages), contains(contains('we see you need Companion Care')));
    });

    test('interpolates {tier} as Critical Care for a catheter-support patient', () {
      final messages = resolveMessages(
        _seedTemplates(),
        [
          _requirement(
            status: 'active',
            careReceiver: _careReceiverJson(toiletAssistance: const ['uses_catheter']),
          ),
        ],
        const [],
      );
      expect(_texts(messages), contains(contains('we see you need Critical Care')));
    });

    test('returns exactly 4 messages once a care_receiver is present on a live requirement', () {
      final messages = resolveMessages(
        _seedTemplates(),
        [_requirement(status: 'active', careReceiver: _careReceiverJson())],
        const [],
      );
      expect(messages, hasLength(4));
    });

    test('returns exactly 3 messages when there is no care_receiver yet', () {
      final messages = resolveMessages(_seedTemplates(), [_requirement(status: 'pending_review')], const []);
      expect(messages, hasLength(3));
    });

    test('icon comes from the admin-set template, not a tier-dependent switch', () {
      // Unlike the old hardcoded behavior, the tier message's icon is now
      // whatever admin picked for that template — same icon regardless of
      // which tier gets interpolated into the text.
      final companion = resolveMessages(
        _seedTemplates(),
        [_requirement(status: 'active', careReceiver: _careReceiverJson())],
        const [],
      );
      final critical = resolveMessages(
        _seedTemplates(),
        [
          _requirement(
            status: 'active',
            careReceiver: _careReceiverJson(toiletAssistance: const ['uses_catheter']),
          ),
        ],
        const [],
      );
      final companionTierMessage = companion.firstWhere((m) => m.text.contains('we see you need'));
      final criticalTierMessage = critical.firstWhere((m) => m.text.contains('we see you need'));
      expect(companionTierMessage.icon, Icons.favorite);
      expect(criticalTierMessage.icon, Icons.favorite);
    });

    test('messages are ordered by displayOrder, interleaving across events as admin set it up', () {
      // Put the tier message (event requirementCareTier) FIRST via order,
      // ahead of the requirementLive messages — confirms ordering is one
      // global sort, not grouped per event.
      final reordered = [
        _template(id: 'a', event: MessageEvent.requirementCareTier, message: 'tier {tier}', displayOrder: 1),
        _template(id: 'b', event: MessageEvent.requirementLive, message: 'salary tip', displayOrder: 2),
        _template(id: 'c', event: MessageEvent.requirementLive, message: 'scope tip', displayOrder: 3),
      ];
      final messages = resolveMessages(
        reordered,
        [_requirement(status: 'active', careReceiver: _careReceiverJson())],
        const [],
      );
      expect(messages.map((m) => m.text).toList(), [
        contains('tier Companion Care'),
        'salary tip',
        'scope tip',
      ]);
    });
  });

  group('resolveMessages — welcome', () {
    test('shows the welcome/orientation messages for an account with no requirements at all', () {
      final messages = resolveMessages(_seedTemplates(), const [], const []);
      expect(messages, hasLength(2));
      expect(_texts(messages), contains(contains('Welcome to NurseNow')));
      expect(_texts(messages), contains(contains('Post a Requirement')));
    });

    test('is empty once the account has posted at least one requirement, even a closed one', () {
      expect(resolveMessages(_seedTemplates(), [_requirement(status: 'closed')], const []), isEmpty);
      expect(resolveMessages(_seedTemplates(), [_requirement(status: 'active')], const []), isNotEmpty);
      expect(resolveMessages(_seedTemplates(), [_requirement(status: 'pending_review')], const []), isNotEmpty);
    });
  });

  group('resolveMessages — caregiver application events', () {
    final applicationTemplates = [
      _template(id: 'applied', event: MessageEvent.caregiverApplied, message: 'Someone applied', displayOrder: 10),
      _template(
          id: 'accepted', event: MessageEvent.caregiverAccepted, message: 'You accepted someone', displayOrder: 20),
      _template(
          id: 'rejected', event: MessageEvent.caregiverRejected, message: 'A candidate was rejected', displayOrder: 30),
      _template(
          id: 'closed', event: MessageEvent.caregiverClosed, message: 'A caregiver closed it', displayOrder: 40),
    ];

    test('shows the applied tip when the most recent requirement has an applied application', () {
      final messages = resolveMessages(
        applicationTemplates,
        [_requirement(status: 'active')],
        [_application(status: 'applied')],
      );
      expect(_texts(messages), [contains('Someone applied')]);
    });

    test('shows the accepted tip even though acceptance closes the requirement (no longer "live")', () {
      final messages = resolveMessages(
        applicationTemplates,
        [_requirement(status: 'closed')],
        [_application(status: 'accepted')],
      );
      expect(_texts(messages), [contains('You accepted someone')]);
    });

    test('shows the rejected tip when a candidate was rejected', () {
      final messages = resolveMessages(
        applicationTemplates,
        [_requirement(status: 'active')],
        [_application(status: 'rejected')],
      );
      expect(_texts(messages), [contains('A candidate was rejected')]);
    });

    test('shows the closed tip when the accepted caregiver closed the engagement', () {
      final messages = resolveMessages(
        applicationTemplates,
        [_requirement(status: 'closed')],
        [_application(status: 'completed')],
      );
      expect(_texts(messages), [contains('A caregiver closed it')]);
    });

    test('shows applied AND accepted together when one candidate is accepted and another still awaits a decision',
        () {
      // Not mutually exclusive — the still-undecided candidate's "applied"
      // tip and the accepted candidate's "accepted" tip both apply at once.
      final messages = resolveMessages(
        applicationTemplates,
        [_requirement(status: 'closed')],
        [_application(id: 'a1', status: 'accepted'), _application(id: 'a2', status: 'applied')],
      );
      expect(_texts(messages).toSet(), {'Someone applied', 'You accepted someone'});
    });

    test('only evaluates the most recent requirement — an older requirement\'s applications do not leak in', () {
      // requirements[0] is "most recent" per the API's created_at DESC
      // ordering; the passed-in applications belong to that one only.
      final messages = resolveMessages(
        applicationTemplates,
        [_requirement(id: 'job-2', status: 'active'), _requirement(id: 'job-1', status: 'closed')],
        [_application(jobId: 'job-2', status: 'applied')],
      );
      expect(_texts(messages), [contains('Someone applied')]);
    });

    test('needsApplicationsFetch is false with no requirements or a pending_review most-recent one', () {
      expect(needsApplicationsFetch(const []), isFalse);
      expect(needsApplicationsFetch([_requirement(status: 'pending_review')]), isFalse);
    });

    test('needsApplicationsFetch is true once the most recent requirement is active or closed', () {
      expect(needsApplicationsFetch([_requirement(status: 'active')]), isTrue);
      expect(needsApplicationsFetch([_requirement(status: 'closed')]), isTrue);
    });
  });
}
