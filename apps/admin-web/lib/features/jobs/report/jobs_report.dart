import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vitacare_shared/vitacare_shared.dart';

import '../../organisation_requirements/data/admin_organisation_requirements_repository.dart';
import '../../organisation_requirements/widgets/requirement_widgets.dart' show requirementDisplayId;

/// Where the app is downloaded; printed, and linked as a QR code, on every
/// page of the report.
const justHealPlayStoreUrl = 'https://play.google.com/store/apps/details?id=in.vitacasahealth.justheal';

class ReportField {
  final String label;
  final String value;
  const ReportField(this.label, this.value);
}

class ReportSection {
  final String title;
  final List<ReportField> fields;
  const ReportSection(this.title, this.fields);
}

/// One job or organisation requirement in the report.
class JobsReportEntry {
  final String id;
  final String status;
  final List<ReportSection> sections;
  const JobsReportEntry(
      {required this.id, required this.status, required this.sections});
}

String _label(Map<String, String> names, String? key) =>
    key == null ? '-' : (names[key] ?? key);

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _formatDateTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '${_formatDate(d)}, $hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
}

String _date(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : _formatDate(parsed.toLocal());
}

String _list(Iterable<String> values) => values.isEmpty ? '-' : values.join(', ');

String _status(String status) => switch (status) {
      JobStatus.pendingReview => 'Pending review',
      JobStatus.active => 'Active',
      JobStatus.closed => 'Closed',
      _ => status,
    };

String _salary(JobModel job) {
  final amount = job.salaryAmount;
  if (amount == null || amount.trim().isEmpty) return '-';
  final unit = job.frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month';
  // A Rate Card suggestion can be a sentence; only a plain number gets a unit.
  return RegExp(r'^\d+$').hasMatch(amount.trim()) ? '₹$amount per $unit' : amount;
}

/// What goes into the report. Deliberately left out: admin's internal notes,
/// the patient's name, and the poster's name and phone — this is a document
/// that may be shared, so it carries the job, pay, patient condition and
/// location only.
JobsReportEntry jobReportEntry(JobModel job) {
    final care = job.careReceiver;
    return JobsReportEntry(
      id: jobDisplayId(job),
      status: _status(job.status),
      sections: [
        ReportSection('Location', [
          ReportField('City', _label(City.displayNames, job.city)),
          ReportField('Area', job.area ?? '-'),
        ]),
        ReportSection('Job and pay', [
          ReportField('Salary', _salary(job)),
          ReportField('Hours care needed', _label(DutyType.displayNames, job.dutyType)),
          ReportField('Care needed for', _label(CareDuration.displayNames, job.careDuration)),
          ReportField('Posted', _date(job.postedAt)),
        ]),
        if (care != null)
          ReportSection('Patient condition', [
            ReportField('Age', '${care.age}'),
            ReportField('Gender', care.gender.isEmpty ? '-' : '${care.gender[0].toUpperCase()}${care.gender.substring(1)}'),
            ReportField('Weight', '${care.weightKg} kg'),
            ReportField(
              'Medical condition',
              care.hasMedicalCondition
                  ? _list([
                      ...care.medicalConditions
                          .where((c) => c != MedicalCondition.other)
                          .map((c) => _label(MedicalCondition.displayNames, c)),
                      if (care.medicalConditions.contains(MedicalCondition.other))
                        (care.medicalConditionOther?.trim().isNotEmpty ?? false)
                            ? 'Other: ${care.medicalConditionOther!.trim()}'
                            : 'Other',
                    ])
                  : 'None',
            ),
            ReportField('Feeding', _label(FeedingType.displayNames, care.feedingType)),
            ReportField(
              'Toilet assistance',
              _list(care.toiletAssistance.map((t) => t == ToiletAssistance.others &&
                      (care.toiletAssistanceOther?.trim().isNotEmpty ?? false)
                  ? 'Other: ${care.toiletAssistanceOther!.trim()}'
                  : _label(ToiletAssistance.displayNames, t))),
            ),
          ]),
        ReportSection('Caregiver preference', [
          ReportField('Gender', _label(const {'male': 'Male', 'female': 'Female'}, job.preferredGender ?? 'No preference')),
          ReportField('Languages', _list(job.languages.map((l) => _label(Language.displayNames, l)))),
          ReportField('Religion', job.preferredReligion == null ? 'No preference' : _label(Religion.displayNames, job.preferredReligion)),
        ]),
      ],
    );
}

JobsReportEntry requirementReportEntry(AdminOrganisationRequirement r) {
    return JobsReportEntry(
      id: requirementDisplayId(r),
      status: _status(r.status),
      sections: [
        ReportSection('Location', [
          ReportField('Organisation', r.organisationName ?? '-'),
          ReportField('Type', _label(OrganisationType.displayNames, r.organisationType)),
          ReportField('City', _label(City.displayNames, r.city)),
          ReportField('Area', r.area ?? '-'),
        ]),
        ReportSection('Requirement', [
          ReportField(
              'Type of nurse',
              r.typeOfNurse == TypeOfNurse.others && (r.typeOfNurseOther?.trim().isNotEmpty ?? false)
                  ? 'Other: ${r.typeOfNurseOther!.trim()}'
                  : _label(TypeOfNurse.displayNames, r.typeOfNurse)),
          ReportField('Vacancies', '${r.numberOfVacancies}'),
          ReportField('Accommodation', r.accommodationProvided ? 'Provided' : 'Not provided'),
          ReportField('Food', r.foodProvided ? 'Provided' : 'Not provided'),
          if (r.specialSkills?.trim().isNotEmpty ?? false) ReportField('Special skills', r.specialSkills!.trim()),
          ReportField('Posted', _date(r.postedAt)),
        ]),
      ],
    );
}

List<JobsReportEntry> buildJobsReportEntries({
  required List<JobModel> jobs,
  required List<AdminOrganisationRequirement> requirements,
}) =>
    [...jobs.map(jobReportEntry), ...requirements.map(requirementReportEntry)];


/// A PDF of [entries], with [filterSummary] stating what the list was
/// narrowed to. Roboto is embedded so the rupee sign prints.
Future<Uint8List> buildJobsReportPdf({
  required List<JobsReportEntry> entries,
  required String filterSummary,
  required DateTime generatedAt,
  required ByteData regularFont,
  required ByteData boldFont,
  bool compress = true,
}) async {
  final regular = pw.Font.ttf(regularFont);
  final bold = pw.Font.ttf(boldFont);
  final doc = pw.Document(
    title: 'VitaCare jobs report',
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    compress: compress,
  );
  const pageMargin = 32.0;
  const muted = PdfColor.fromInt(0xFF5F6B7A);
  const rule = PdfColor.fromInt(0xFFD0D5DD);

  pw.Widget section(ReportSection s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(s.title,
              style: pw.TextStyle(font: bold, fontSize: 9, color: muted)),
          pw.SizedBox(height: 2),
          for (final f in s.fields)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.SizedBox(width: 110, child: pw.Text(f.label, style: const pw.TextStyle(fontSize: 9.5, color: muted))),
                pw.Expanded(child: pw.Text(f.value, style: const pw.TextStyle(fontSize: 9.5))),
              ]),
            ),
        ]),
      );

  pw.Widget entry(JobsReportEntry e) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: rule), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(e.id, style: pw.TextStyle(font: bold, fontSize: 12)),
            pw.Text(e.status, style: const pw.TextStyle(fontSize: 10, color: muted)),
          ]),
          for (final s in e.sections) section(s),
        ]),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(pageMargin),
    header: (context) => context.pageNumber == 1
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text('VitaCare jobs report', style: const pw.TextStyle(fontSize: 9, color: muted))),
    footer: (context) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(children: [
        // On every page: invites whoever reads the report to get the app.
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFE6F4F1),
            border: pw.Border.all(color: const PdfColor.fromInt(0xFF1F8F7A), width: 1),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Download the JustHeal app',
                    style: pw.TextStyle(font: bold, fontSize: 13, color: const PdfColor.fromInt(0xFF146B5B))),
                pw.SizedBox(height: 2),
                pw.Text('Scan the QR code or open the link on your phone.',
                    style: const pw.TextStyle(fontSize: 9.5)),
                pw.SizedBox(height: 2),
                pw.UrlLink(
                  destination: justHealPlayStoreUrl,
                  child: pw.Text(justHealPlayStoreUrl,
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColor.fromInt(0xFF1A56DB), decoration: pw.TextDecoration.underline)),
                ),
              ]),
            ),
            pw.SizedBox(width: 10),
            pw.UrlLink(
              destination: justHealPlayStoreUrl,
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: justHealPlayStoreUrl,
                width: 58,
                height: 58,
              ),
            ),
          ]),
        ),
        pw.SizedBox(height: 4),
        pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: muted))),
      ]),
    ),
    build: (context) => [
      pw.Text('VitaCare jobs report', style: pw.TextStyle(font: bold, fontSize: 18)),
      pw.SizedBox(height: 4),
      pw.Text('Generated ${_formatDateTime(generatedAt)}  ·  ${entries.length} ${entries.length == 1 ? 'job' : 'jobs'}',
          style: const pw.TextStyle(fontSize: 10, color: muted)),
      pw.Text(filterSummary, style: const pw.TextStyle(fontSize: 10, color: muted)),
      pw.SizedBox(height: 12),
      // A Wrap places whole children, so a card moves to the next page
      // rather than splitting across two.
      pw.Wrap(children: [
        for (final e in entries) pw.SizedBox(width: PdfPageFormat.a4.width - 2 * pageMargin, child: entry(e)),
      ]),
    ],
  ));
  return doc.save();
}
