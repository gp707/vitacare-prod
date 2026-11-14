import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:admin_web/features/jobs/report/jobs_report.dart';
import 'package:admin_web/features/organisation_requirements/data/admin_organisation_requirements_repository.dart';

JobModel _patientJob({String salary = '30000'}) => JobModel.fromJson({
      'id': 'job-1',
      'patient_job_number': 551,
      'city': 'bangalore',
      'area': 'Whitefield',
      'duty_type': 'live_in',
      'frequency_of_care': 'monthly',
      'start_date': '2026-12-01',
      'care_duration': 'long_term',
      'languages': ['hindi', 'english'],
      'salary_amount': salary,
      'preferred_gender': 'female',
      'status': 'active',
      'posted_by': 'patient-1',
      'posted_at': '2026-11-14T10:00:00Z',
      'created_at': '2026-11-14T10:00:00Z',
      'posted_by_role': 'individual',
      'posted_by_name': 'Secret Poster Name',
      'posted_by_phone': '+919999900000',
      'notes': 'INTERNAL: family is difficult, do not send nurse X',
      'care_receiver': {
        'id': 'cr-1',
        'patient_name': 'Secret Patient Name',
        'age': 72,
        'gender': 'female',
        'weight_kg': 58,
        'feeding_type': 'tube_feeding',
        'has_medical_condition': true,
        'medical_conditions': ['diabetes', 'other'],
        'medical_condition_other': 'Hip replacement',
        'toilet_assistance': ['uses_catheter'],
        'requires_vital_monitoring': false,
        'vital_monitoring_types': [],
      },
    });

AdminOrganisationRequirement _requirement() => AdminOrganisationRequirement(
      id: 'r1',
      requirementNumber: 600,
      postedBy: 'org-1',
      typeOfNurse: TypeOfNurse.auxiliaryNurse,
      accommodationProvided: true,
      foodProvided: false,
      numberOfVacancies: 3,
      status: JobStatus.active,
      postedAt: '2026-11-14T10:00:00Z',
      organisationName: 'City Rehab Center',
      organisationType: OrganisationType.rehab,
      city: City.bangalore,
      area: 'Whitefield',
      contactPersonName: 'Secret Contact',
      organisationPhone: '+918888800000',
      notes: 'INTERNAL: org note',
    );

String _everything(List<JobsReportEntry> entries) => entries
    .expand((e) => [e.id, e.status, ...e.sections.expand((s) => [s.title, ...s.fields.expand((f) => [f.label, f.value])])])
    .join('\n');

Map<String, String> _fields(JobsReportEntry e) =>
    {for (final s in e.sections) for (final f in s.fields) '${s.title}/${f.label}': f.value};

void main() {
  test('a job carries location, salary and patient condition', () {
    final fields = _fields(jobReportEntry(_patientJob()));
    expect(jobReportEntry(_patientJob()).id, 'PAT-JOB-551');
    expect(fields['Location/City'], 'Bangalore');
    expect(fields['Location/Area'], 'Whitefield');
    expect(fields['Job and pay/Salary'], '₹30000 per month');
    expect(fields['Patient condition/Age'], '72');
    expect(fields['Patient condition/Weight'], '58 kg');
    expect(fields['Patient condition/Medical condition'], contains('Diabetes'));
    expect(fields['Patient condition/Medical condition'], contains('Other: Hip replacement'));
    expect(fields['Patient condition/Feeding'], 'Tube feeding');
    expect(fields['Patient condition/Toilet assistance'], 'Catheter support');
  });

  test('a salary that is a sentence is shown as written, without a unit stuck on', () {
    final fields = _fields(jobReportEntry(_patientJob(salary: '26000 pm to 30000 pm depending on experience')));
    expect(fields['Job and pay/Salary'], '26000 pm to 30000 pm depending on experience');
  });

  test('internal notes, the patient name, and the poster name/phone never appear', () {
    final text = _everything(buildJobsReportEntries(jobs: [_patientJob()], requirements: [_requirement()]));
    expect(text, isNot(contains('INTERNAL')));
    expect(text, isNot(contains('Secret Patient Name')));
    expect(text, isNot(contains('Secret Poster Name')));
    expect(text, isNot(contains('+919999900000')));
    expect(text, isNot(contains('Secret Contact')));
    expect(text, isNot(contains('+918888800000')));
  });

  test('an organisation requirement carries its location and what it needs', () {
    final entry = requirementReportEntry(_requirement());
    final fields = _fields(entry);
    expect(entry.id, 'ORG-JOB-600');
    expect(fields['Location/Organisation'], 'City Rehab Center');
    expect(fields['Location/City'], 'Bangalore');
    expect(fields['Requirement/Vacancies'], '3');
    expect(fields['Requirement/Accommodation'], 'Provided');
    expect(fields['Requirement/Food'], 'Not provided');
  });

  test('builds a real PDF', () async {
    ByteData font(String name) =>
        ByteData.sublistView(Uint8List.fromList(File('assets/fonts/$name').readAsBytesSync()));
    final bytes = await buildJobsReportPdf(
      entries: buildJobsReportEntries(jobs: [_patientJob()], requirements: [_requirement()]),
      filterSummary: 'Filters: City: Bangalore',
      generatedAt: DateTime(2026, 11, 14, 15, 30),
      regularFont: font('Roboto-Regular.ttf'),
      boldFont: font('Roboto-Bold.ttf'),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });
}
