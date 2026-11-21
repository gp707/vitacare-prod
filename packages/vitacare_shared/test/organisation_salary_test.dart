import 'package:test/test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

Map<String, dynamic> _req([Map<String, dynamic> extra = const {}]) => {
      'id': 'r1',
      'requirement_number': 574,
      'posted_by': 'u1',
      'type_of_nurse': 'registered_nurse',
      'accommodation_provided': true,
      'food_provided': true,
      'number_of_vacancies': 1,
      'status': 'active',
      'posted_at': '2026-11-21T10:00:00Z',
      ...extra,
    };

void main() {
  group('an organisation requirement\'s salary range', () {
    test('has none until the organisation gives one', () {
      final r = OrganisationRequirementModel.fromJson(_req());
      expect(r.hasSalaryRange, isFalse);
      expect(salaryRangeLabel(r), isNull);
    });

    test('reads as "₹min – ₹max per month" or per day', () {
      final monthly = OrganisationRequirementModel.fromJson(_req({'salary_min': 20000, 'salary_max': 30000, 'salary_unit': 'monthly'}));
      expect(monthly.hasSalaryRange, isTrue);
      expect(salaryRangeLabel(monthly), '₹20,000 – ₹30,000 per month');
      final daily = OrganisationRequirementModel.fromJson(_req({'salary_min': 800, 'salary_max': 1200, 'salary_unit': 'daily'}));
      expect(salaryRangeLabel(daily), '₹800 – ₹1,200 per day');
    });

    test('equal ends read as one figure', () {
      final r = OrganisationRequirementModel.fromJson(_req({'salary_min': 900, 'salary_max': 900, 'salary_unit': 'daily'}));
      expect(salaryRangeLabel(r), '₹900 per day');
    });

    test('a half-filled range (should never happen) is treated as no range', () {
      final r = OrganisationRequirementModel.fromJson(_req({'salary_min': 900}));
      expect(r.hasSalaryRange, isFalse);
      expect(salaryRangeLabel(r), isNull);
    });
  });

  group('an organisation\'s applicant carries the agreed salary and start date and its history', () {
    Map<String, dynamic> app([Map<String, dynamic> extra = const {}]) => {
          'id': 'a1',
          'requirement_id': 'r1',
          'profile_id': 'p1',
          'status': 'accepted',
          'full_name': 'Asha Rao',
          'phone': '+919999999999',
          'updated_at': '2026-11-21T10:00:00Z',
          ...extra,
        };

    test('nothing agreed yet', () {
      final a = OrganisationRequirementApplicationModel.fromJson(app());
      expect(a.agreedSalary, isNull);
      expect(a.agreedStartDate, isNull);
      expect(a.agreementHistory, isEmpty);
    });

    test('reads the agreement and every change, oldest first', () {
      final a = OrganisationRequirementApplicationModel.fromJson(app({
        'agreed_salary': 25000,
        'agreed_salary_unit': 'monthly',
        'agreed_start_date': '2026-12-01',
        'agreement_history': [
          {'salary': 20000, 'unit': 'monthly', 'start_date': '2026-11-25', 'at': '2026-11-20T10:00:00Z'},
          {'salary': 25000, 'unit': 'monthly', 'start_date': '2026-12-01', 'at': '2026-11-21T10:00:00Z'},
        ],
      }));
      expect(a.agreedSalary, 25000);
      expect(a.agreedSalaryUnit, 'monthly');
      expect(a.agreedStartDate, '2026-12-01');
      expect(a.agreementHistory, hasLength(2));
      expect(a.agreementHistory.first.summary, '₹20,000 per month, starts 25 Nov 2026');
    });
  });

  group('the caregiver\'s own view of an organisation requirement carries the agreement', () {
    test('my_application has the agreed terms and history', () {
      final r = OrganisationRequirementModel.fromJson(_req({
        'my_application': {
          'status': 'accepted',
          'decided_by_admin': false,
          'agreed_salary': 25000,
          'agreed_salary_unit': 'monthly',
          'agreed_start_date': '2026-12-01',
          'agreement_history': [
            {'salary': 25000, 'unit': 'monthly', 'start_date': '2026-12-01', 'at': '2026-11-21T10:00:00Z'},
          ],
        },
      }));
      expect(r.myApplication!.agreedSalary, 25000);
      expect(r.myApplication!.agreedStartDate, '2026-12-01');
      expect(r.myApplication!.agreementHistory, hasLength(1));
    });
  });

  test('the two new organisation routes', () {
    expect(ApiRoutes.organisationRequirementSalaryRange('r1'), '/organisation/requirements/r1/salary-range');
    expect(ApiRoutes.organisationRequirementApplicationAgreement('r1', 'a1'),
        '/organisation/requirements/r1/applications/a1/agreement');
  });
}
