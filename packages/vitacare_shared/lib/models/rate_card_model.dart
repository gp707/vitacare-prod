/// Mirrors the `GET /rate-card` / `GET /admin/rate-card` response — a
/// single admin-editable salary-guideline grid, shown behind a persistent
/// app-bar icon on caregiver-app (NurseJobs) and nursenow-app's Individual
/// (patient/family) screens only — never shown to Organisation accounts,
/// since these guidelines are for individual hiring, not institutional bulk
/// hiring. `columnLabels`/`rowLabels` are always exactly 3 entries each,
/// `cells[row][col]` a matching 3x3 grid of free-text strings — the shape
/// is fixed for now, only the text content is admin-editable.
class RateCardModel {
  final String title;
  final List<String> columnLabels;
  final List<String> rowLabels;
  final List<List<String>> cells;

  const RateCardModel({
    required this.title,
    required this.columnLabels,
    required this.rowLabels,
    required this.cells,
  });

  factory RateCardModel.fromJson(Map<String, dynamic> json) => RateCardModel(
        title: json['title'] as String,
        columnLabels: (json['column_labels'] as List).map((e) => e as String).toList(),
        rowLabels: (json['row_labels'] as List).map((e) => e as String).toList(),
        cells: (json['cells'] as List)
            .map((row) => (row as List).map((cell) => cell as String).toList())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'column_labels': columnLabels,
        'row_labels': rowLabels,
        'cells': cells,
      };
}
