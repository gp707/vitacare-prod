import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../app_maintenance/data/app_maintenance_repository.dart';

/// Same local-helper convention as app_versions_settings_section.dart.
String _appDisplayName(String app) => app == 'nursejobs' ? 'NurseJobs' : 'NurseNow';

/// The "Maintenance Mode" tab of the Settings hub — lets an admin take
/// either mobile app down entirely with a custom message (e.g. "App is in
/// maintenance mode, it will be available after 10am IST"). Enabling this
/// blocks every user of that app with a non-dismissible full-screen notice
/// on their next launch, checked before login (see
/// AppMaintenanceRepository.checkForMaintenance in each app). NurseJobs and
/// NurseNow are switched independently of each other — each is its own
/// bordered box with its own Save button, same pattern as Rate Card's
/// per-frequency sections.
class MaintenanceSettingsSection extends ConsumerStatefulWidget {
  const MaintenanceSettingsSection({super.key});

  @override
  ConsumerState<MaintenanceSettingsSection> createState() => _MaintenanceSettingsSectionState();
}

class _MaintenanceSettingsSectionState extends ConsumerState<MaintenanceSettingsSection> {
  bool _loading = true;
  String? _errorMessage;
  List<AppMaintenance>? _rows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final rows = await ref.read(appMaintenanceRepositoryProvider).list();
      if (mounted) setState(() => _rows = rows);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: VitaLoadingIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Take an app down entirely for maintenance, with a custom message shown to '
            'every user on their next launch (e.g. "App is in maintenance mode, it will be '
            'available after 10am IST"). NurseJobs and NurseNow are switched independently.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
          else
            for (final row in _rows!)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                child: _MaintenanceAppSection(
                  key: ValueKey(row.app),
                  initial: row,
                ),
              ),
        ],
      ),
    );
  }
}

class _MaintenanceAppSection extends ConsumerStatefulWidget {
  final AppMaintenance initial;

  const _MaintenanceAppSection({super.key, required this.initial});

  @override
  ConsumerState<_MaintenanceAppSection> createState() => _MaintenanceAppSectionState();
}

class _MaintenanceAppSectionState extends ConsumerState<_MaintenanceAppSection> {
  bool _saving = false;
  String? _errorMessage;
  late bool _enabled;
  late String? _updatedByName;
  late String _updatedAt;
  late TextEditingController _messageController;

  String get _app => widget.initial.app;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initial.enabled;
    _updatedByName = widget.initial.updatedByName;
    _updatedAt = widget.initial.updatedAt;
    _messageController = TextEditingController(text: widget.initial.message ?? '');
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final repository = ref.read(appMaintenanceRepositoryProvider);
      await repository.update(_app, enabled: _enabled, message: _messageController.text.trim());
      // Re-fetch to pick up the server-set updated_by/updated_at — the
      // update endpoint itself only returns void.
      final refreshed = await repository.list();
      final own = refreshed.firstWhere((r) => r.app == _app);
      if (mounted) {
        setState(() {
          _updatedByName = own.updatedByName;
          _updatedAt = own.updatedAt;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_appDisplayName(_app)} maintenance settings saved')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build_circle_outlined, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _appDisplayName(_app),
                style: const TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Maintenance mode'),
            subtitle: Text(_enabled
                ? 'Every user is blocked with the message below on their next launch.'
                : 'The app is available as normal.'),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _messageController,
            decoration: const InputDecoration(
              labelText: 'Message shown to users',
              hintText: 'App is in maintenance mode, it will be available after 10am IST.',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Last updated by ${_updatedByName ?? '-'} on $_updatedAt',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
          ),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
