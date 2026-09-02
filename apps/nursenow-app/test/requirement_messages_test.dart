import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/features/individual/data/requirement_messages.dart';

JobModel _requirement({
  String status = 'active',
  Map<String, dynamic>? careReceiver,
}) {
  return JobModel.fromJson({
    'id': 'job-1',
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
      'communication': 'verbal',
      'feeding_type': feedingType,
      'has_medical_condition': false,
      'medical_conditions': [],
      'toilet_assistance': toiletAssistance,
      'requires_vital_monitoring': false,
      'vital_monitoring_types': [],
    };

Iterable<String> _texts(List<MessageItem> messages) => messages.map((m) => m.text);

void main() {
  group('messagesForRequirement', () {
    test('returns nothing for a closed requirement', () {
      expect(messagesForRequirement(_requirement(status: 'closed')), isEmpty);
    });

    test('includes the edit/salary tip for a pending_review requirement', () {
      final messages = messagesForRequirement(_requirement(status: 'pending_review'));
      expect(
        _texts(messages),
        contains(contains('You can edit this job and change salary')),
      );
    });

    test('includes the edit/salary tip for an active requirement', () {
      final messages = messagesForRequirement(_requirement(status: 'active'));
      expect(
        _texts(messages),
        contains(contains('You can edit this job and change salary')),
      );
    });

    test('includes the one-requirement-at-a-time tip while live', () {
      final messages = messagesForRequirement(_requirement(status: 'active'));
      expect(
        _texts(messages),
        contains(contains('You can post one requirement at a time')),
      );
    });

    test('includes the widen-your-scope tip while live', () {
      final messages = messagesForRequirement(_requirement(status: 'active'));
      expect(
        _texts(messages),
        contains(contains('consider widening your scope')),
      );
    });

    test('omits the derived-tier tip when there is no care_receiver yet', () {
      final messages = messagesForRequirement(_requirement(status: 'pending_review'));
      expect(messages.any((m) => m.text.contains('we see you need')), isFalse);
    });

    test('includes the derived-tier tip naming Companion Care for an independent/oral-feeding patient', () {
      final messages = messagesForRequirement(
        _requirement(status: 'active', careReceiver: _careReceiverJson()),
      );
      expect(
        _texts(messages),
        contains(contains("we see you need Companion Care")),
      );
    });

    test('includes the derived-tier tip naming Critical Care for a catheter-support patient', () {
      final messages = messagesForRequirement(
        _requirement(
          status: 'active',
          careReceiver: _careReceiverJson(toiletAssistance: const ['uses_catheter']),
        ),
      );
      expect(
        _texts(messages),
        contains(contains('we see you need Critical Care')),
      );
    });

    test('returns exactly 4 messages once a care_receiver is present on a live requirement', () {
      final messages = messagesForRequirement(
        _requirement(status: 'active', careReceiver: _careReceiverJson()),
      );
      expect(messages, hasLength(4));
    });

    test('returns exactly 3 messages when there is no care_receiver yet', () {
      final messages = messagesForRequirement(_requirement(status: 'pending_review'));
      expect(messages, hasLength(3));
    });

    test('every row gets its own distinct icon, not a repeated generic one', () {
      final messages = messagesForRequirement(
        _requirement(status: 'active', careReceiver: _careReceiverJson()),
      );
      final icons = messages.map((m) => m.icon).toSet();
      expect(icons, hasLength(4));
    });

    test('the derived-tier row uses the same pictogram Scope of Work uses for that tier', () {
      final companion = messagesForRequirement(
        _requirement(status: 'active', careReceiver: _careReceiverJson()),
      );
      final critical = messagesForRequirement(
        _requirement(
          status: 'active',
          careReceiver: _careReceiverJson(toiletAssistance: const ['uses_catheter']),
        ),
      );
      final companionTierMessage = companion.firstWhere((m) => m.text.contains('we see you need'));
      final criticalTierMessage = critical.firstWhere((m) => m.text.contains('we see you need'));
      expect(companionTierMessage.icon, Icons.favorite);
      expect(criticalTierMessage.icon, Icons.emergency);
    });
  });

  group('welcomeMessages', () {
    test('shows the welcome/orientation messages for an account with no requirements at all', () {
      final messages = welcomeMessages(const []);
      expect(messages, hasLength(2));
      expect(_texts(messages), contains(contains('Welcome to NurseNow')));
      expect(_texts(messages), contains(contains('Post a Requirement')));
    });

    test('is empty once the account has posted at least one requirement, even a closed one', () {
      expect(welcomeMessages([_requirement(status: 'closed')]), isEmpty);
      expect(welcomeMessages([_requirement(status: 'active')]), isEmpty);
      expect(welcomeMessages([_requirement(status: 'pending_review')]), isEmpty);
    });
  });
}
