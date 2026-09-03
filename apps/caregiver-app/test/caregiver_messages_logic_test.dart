import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/features/jobs/data/caregiver_messages_logic.dart';

JobModel _job({
  String id = 'job-1',
  int? adminJobNumber = 512,
  Map<String, dynamic>? myApplication,
}) {
  return JobModel.fromJson({
    'id': id,
    'admin_job_number': adminJobNumber,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'start_date': '2026-09-01',
    'languages': ['hindi'],
    'salary_amount': '1800',
    'status': 'active',
    'posted_by': 'admin-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    if (myApplication != null) 'my_application': myApplication,
  });
}

Map<String, dynamic> _myApplication({
  required String status,
  String? appliedAt,
  String? acceptedAt,
  String? rejectedAt,
  String? completedAt,
}) =>
    {
      'status': status,
      'applied_at': appliedAt,
      'accepted_at': acceptedAt,
      'rejected_at': rejectedAt,
      'completed_at': completedAt,
      'reapplied_at': null,
      'decided_by_admin': false,
      'decline_reason': null,
    };

CaregiverMessageModel _template({
  required String id,
  required String event,
  String icon = MessageIcon.info,
  required String message,
  required int displayOrder,
}) =>
    CaregiverMessageModel(
      id: id,
      event: event,
      icon: icon,
      message: message,
      displayOrder: displayOrder,
      enabled: true,
    );

List<CaregiverMessageModel> _seedTemplates() => [
      _template(
        id: 'm1',
        event: CaregiverMessageEvent.jobApplied,
        icon: MessageIcon.personAdd,
        message: 'Successfully applied to job {job_id}',
        displayOrder: 10,
      ),
      _template(
        id: 'm2',
        event: CaregiverMessageEvent.jobAccepted,
        icon: MessageIcon.checkCircle,
        message: 'Selected by patient for job {job_id}',
        displayOrder: 20,
      ),
      _template(
        id: 'm3',
        event: CaregiverMessageEvent.jobRejected,
        icon: MessageIcon.cancel,
        message: 'Rejected by patient for job {job_id}',
        displayOrder: 30,
      ),
      _template(
        id: 'm4',
        event: CaregiverMessageEvent.jobClosed,
        icon: MessageIcon.taskAlt,
        message: 'You closed job {job_id}',
        displayOrder: 40,
      ),
      _template(
        id: 'm5',
        event: CaregiverMessageEvent.welcome,
        icon: MessageIcon.wavingHand,
        message: 'Welcome to NurseJobs!',
        displayOrder: 10,
      ),
    ];

Iterable<String> _texts(List<CaregiverMessageItem> messages) => messages.map((m) => m.text);

void main() {
  group('resolveCaregiverMessages — welcome', () {
    test('shows welcome when the caregiver has never applied to any job', () {
      final messages = resolveCaregiverMessages(_seedTemplates(), const [], const []);
      expect(messages, hasLength(1));
      expect(_texts(messages), contains(contains('Welcome to NurseJobs')));
    });

    test('is empty once at least one active job carries a my_application', () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        [_job(myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-01T10:00:00Z'))],
        const [],
      );
      expect(messages.any((m) => m.text.contains('Welcome to NurseJobs')), isFalse);
    });

    test('is empty once there is any assigned job at all', () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        const [],
        [_job(myApplication: _myApplication(status: 'accepted', acceptedAt: '2026-08-01T10:00:00Z'))],
      );
      expect(messages.any((m) => m.text.contains('Welcome to NurseJobs')), isFalse);
    });
  });

  group('resolveCaregiverMessages — application events', () {
    test('shows jobApplied and interpolates {job_id} for a currently-active applied job', () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        [_job(adminJobNumber: 512, myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-01T10:00:00Z'))],
        const [],
      );
      expect(_texts(messages), [contains('Successfully applied to job ADMIN-JOB-512')]);
    });

    test('also interpolates the tolerated <job_id> (angle-bracket) form, not just {job_id}', () {
      final templates = [
        _template(
          id: 'm1',
          event: CaregiverMessageEvent.jobApplied,
          message: 'You have successfully applied to the job with id <job_id>',
          displayOrder: 10,
        ),
      ];
      final messages = resolveCaregiverMessages(
        templates,
        [_job(adminJobNumber: 512, myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-01T10:00:00Z'))],
        const [],
      );
      expect(_texts(messages), [contains('You have successfully applied to the job with id ADMIN-JOB-512')]);
      expect(_texts(messages), isNot(contains(contains('<job_id>'))));
    });

    test('shows jobRejected for a currently-active rejected job', () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        [_job(adminJobNumber: 513, myApplication: _myApplication(status: 'rejected', rejectedAt: '2026-08-01T10:00:00Z'))],
        const [],
      );
      expect(_texts(messages), [contains('Rejected by patient for job ADMIN-JOB-513')]);
    });

    test('shows jobAccepted for an assigned job with an accepted application', () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        const [],
        [_job(adminJobNumber: 514, myApplication: _myApplication(status: 'accepted', acceptedAt: '2026-08-01T10:00:00Z'))],
      );
      expect(_texts(messages), [contains('Selected by patient for job ADMIN-JOB-514')]);
    });

    test('shows jobClosed for an assigned job the caregiver completed', () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        const [],
        [_job(adminJobNumber: 515, myApplication: _myApplication(status: 'completed', completedAt: '2026-08-01T10:00:00Z'))],
      );
      expect(_texts(messages), [contains('You closed job ADMIN-JOB-515')]);
    });

    test('a job with no my_application matches no event and is not treated as "ever applied"', () {
      final messages = resolveCaregiverMessages(_seedTemplates(), [_job(myApplication: null)], const []);
      expect(_texts(messages), [contains('Welcome to NurseJobs')]);
    });

    test('shows applied AND accepted together when they come from different jobs', () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        [
          _job(
            id: 'job-a',
            adminJobNumber: 520,
            myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-01T10:00:00Z'),
          ),
        ],
        [
          _job(
            id: 'job-b',
            adminJobNumber: 521,
            myApplication: _myApplication(status: 'accepted', acceptedAt: '2026-08-02T10:00:00Z'),
          ),
        ],
      );
      expect(_texts(messages).toSet(), {
        'Successfully applied to job ADMIN-JOB-520',
        'Selected by patient for job ADMIN-JOB-521',
      });
    });

    test('fires once per matching job application, newest first, when more than one job matches the same event',
        () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        [
          _job(
            id: 'job-older',
            adminJobNumber: 530,
            myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-01T10:00:00Z'),
          ),
          _job(
            id: 'job-newer',
            adminJobNumber: 531,
            myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-05T10:00:00Z'),
          ),
        ],
        const [],
      );
      expect(messages.map((m) => m.text).toList(), [
        contains('Successfully applied to job ADMIN-JOB-531'),
        contains('Successfully applied to job ADMIN-JOB-530'),
      ]);
    });

    test('each job-scoped message has a distinct id, keyed by both the template and the job', () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        [
          _job(
            id: 'job-a',
            adminJobNumber: 550,
            myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-01T10:00:00Z'),
          ),
          _job(
            id: 'job-b',
            adminJobNumber: 551,
            myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-02T10:00:00Z'),
          ),
        ],
        const [],
      );
      expect(messages.map((m) => m.id).toSet(), {'m1:job-a', 'm1:job-b'});
    });

    test('applying to 3 jobs shows 3 separate applied messages, each with its own real job id', () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        [
          _job(id: 'j1', adminJobNumber: 601, myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-01T10:00:00Z')),
          _job(id: 'j2', adminJobNumber: 602, myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-02T10:00:00Z')),
          _job(id: 'j3', adminJobNumber: 603, myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-03T10:00:00Z')),
        ],
        const [],
      );
      expect(messages, hasLength(3));
      expect(_texts(messages).toSet(), {
        'Successfully applied to job ADMIN-JOB-601',
        'Successfully applied to job ADMIN-JOB-602',
        'Successfully applied to job ADMIN-JOB-603',
      });
    });

    test('messages are ordered by displayOrder, interleaving across events as admin set it up', () {
      final reordered = [
        _template(id: 'a', event: CaregiverMessageEvent.jobAccepted, message: 'accepted {job_id}', displayOrder: 1),
        _template(id: 'b', event: CaregiverMessageEvent.jobApplied, message: 'applied {job_id}', displayOrder: 2),
      ];
      final messages = resolveCaregiverMessages(
        reordered,
        [_job(adminJobNumber: 540, myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-01T10:00:00Z'))],
        [_job(id: 'job-2', adminJobNumber: 541, myApplication: _myApplication(status: 'accepted', acceptedAt: '2026-08-01T10:00:00Z'))],
      );
      expect(messages.map((m) => m.text).toList(), [
        contains('accepted ADMIN-JOB-541'),
        contains('applied ADMIN-JOB-540'),
      ]);
    });

    test('icon comes from the admin-set template', () {
      final messages = resolveCaregiverMessages(
        _seedTemplates(),
        [_job(myApplication: _myApplication(status: 'applied', appliedAt: '2026-08-01T10:00:00Z'))],
        const [],
      );
      expect(messages.single.icon, Icons.person_add);
    });
  });
}
