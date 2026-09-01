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

void main() {
  group('messagesForRequirement', () {
    test('returns nothing for a closed requirement', () {
      expect(messagesForRequirement(_requirement(status: 'closed')), isEmpty);
    });

    test('includes the edit/salary tip for a pending_review requirement', () {
      final messages = messagesForRequirement(_requirement(status: 'pending_review'));
      expect(
        messages,
        contains(contains('You can edit this job and change salary')),
      );
    });

    test('includes the edit/salary tip for an active requirement', () {
      final messages = messagesForRequirement(_requirement(status: 'active'));
      expect(
        messages,
        contains(contains('You can edit this job and change salary')),
      );
    });

    test('includes the one-requirement-at-a-time tip while live', () {
      final messages = messagesForRequirement(_requirement(status: 'active'));
      expect(
        messages,
        contains(contains('You can post one requirement at a time')),
      );
    });

    test('includes the widen-your-scope tip while live', () {
      final messages = messagesForRequirement(_requirement(status: 'active'));
      expect(
        messages,
        contains(contains('consider widening your scope')),
      );
    });

    test('omits the derived-tier tip when there is no care_receiver yet', () {
      final messages = messagesForRequirement(_requirement(status: 'pending_review'));
      expect(messages.any((m) => m.contains('we see you need')), isFalse);
    });

    test('includes the derived-tier tip naming Companion Care for an independent/oral-feeding patient', () {
      final messages = messagesForRequirement(
        _requirement(status: 'active', careReceiver: _careReceiverJson()),
      );
      expect(
        messages,
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
        messages,
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
  });
}
