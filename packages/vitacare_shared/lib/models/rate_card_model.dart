/// Mirrors one row of the `GET /rate-card` / `GET /admin/rate-card`
/// response — an admin-editable salary-guideline grid, shown behind a
/// persistent app-bar icon on caregiver-app (NurseJobs) and nursenow-app's
/// Individual (patient/family) screens only — never shown to Organisation
/// accounts, since these guidelines are for individual hiring, not
/// institutional bulk hiring. There are always exactly 2 rows, one per
/// [frequencyOfCare] ('daily'/'monthly', see [FrequencyOfCare]) — both
/// endpoints return a list of both, never just one. `columnLabels` is
/// always exactly 3 entries, `rowLabels` always exactly 1 (just "Care"),
/// `cells[row][col]` a matching 1x3 grid of free-text strings — the shape
/// is fixed for now, only the text content is admin-editable.
class RateCardModel {
  final String frequencyOfCare;
  final String title;
  final List<String> columnLabels;
  final List<String> rowLabels;
  final List<List<String>> cells;

  const RateCardModel({
    required this.frequencyOfCare,
    required this.title,
    required this.columnLabels,
    required this.rowLabels,
    required this.cells,
  });

  factory RateCardModel.fromJson(Map<String, dynamic> json) => RateCardModel(
        frequencyOfCare: json['frequency_of_care'] as String,
        title: json['title'] as String,
        columnLabels: (json['column_labels'] as List).map((e) => e as String).toList(),
        rowLabels: (json['row_labels'] as List).map((e) => e as String).toList(),
        cells: (json['cells'] as List)
            .map((row) => (row as List).map((cell) => cell as String).toList())
            .toList(),
      );

  /// [frequencyOfCare] is deliberately excluded — it's the URL path param
  /// on `PATCH /admin/rate-card/:frequency`, never part of the request body.
  Map<String, dynamic> toJson() => {
        'title': title,
        'column_labels': columnLabels,
        'row_labels': rowLabels,
        'cells': cells,
      };
}
