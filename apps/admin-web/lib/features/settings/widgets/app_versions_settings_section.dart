import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../app_versions/data/app_versions_repository.dart';

/// NurseJobs and NurseNow each brand-display as their own name rather than
/// the raw 'nursejobs'/'nursenow' app bucket value — same local-helper
/// convention as e.g. audit_logs_screen.dart's _auditJobDisplayId.
String _appDisplayName(String app) => app == 'nursejobs' ? 'NurseJobs' : 'NurseNow';

/// The "App Versions" tab of the Settings hub — lets an admin force-upgrade
/// either mobile app independently: raising an app+platform's min_version
/// above what a user has installed blocks them with an "Update Required"
/// screen on their next launch (see AppVersionRepository.checkForUpdate in
/// each app). NurseJobs and NurseNow each maintain their own 2 rows
/// (android/ios), grouped into their own section here — 4 rows total (see
/// migration 068).
class AppVersionsSettingsSection extends ConsumerStatefulWidget {
  const AppVersionsSettingsSection({super.key});

  @override
  ConsumerState<AppVersionsSettingsSection> createState() => _AppVersionsSettingsSectionState();
}

class _AppVersionsSettingsSectionState extends ConsumerState<AppVersionsSettingsSection> {
  List<AppMinVersion> _versions = [];
  bool _loading = true;
  String? _errorMessage;

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
      final versions = await ref.read(appVersionsRepositoryProvider).list();
      if (mounted) setState(() => _versions = versions);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showEditDialog(AppMinVersion version) async {
    final minVersionController = TextEditingController(text: version.minVersion);
    final storeUrlController = TextEditingController(text: version.storeUrl ?? '');
    final updateMessageController = TextEditingController(text: version.updateMessage ?? '');
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${_appDisplayName(version.app)} — ${version.platform} minimum version'),
          content: SizedBox(
            width: context.dialogWidth(420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: minVersionController,
                  decoration: const InputDecoration(labelText: 'Minimum version (e.g. 1.2.0)'),
                ),
                TextField(
                  controller: storeUrlController,
                  decoration: const InputDecoration(labelText: 'Store URL'),
                ),
                TextField(
                  controller: updateMessageController,
                  decoration:
                      const InputDecoration(labelText: 'Update message (shown to the user)'),
                  maxLines: 2,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(dialogError!, style: const TextStyle(color: AppColors.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ref.read(appVersionsRepositoryProvider).update(
                        version.app,
                        version.platform,
                        minVersion: minVersionController.text.trim(),
                        storeUrl: storeUrlController.text.trim(),
                        updateMessage: updateMessageController.text.trim(),
                      );
                  if (context.mounted) Navigator.of(context).pop(true);
                } on ApiException catch (e) {
                  setDialogState(() => dialogError = e.message);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) await _load();
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
            'Raise an app\'s minimum version above what a user has installed to '
            'force them to update before they can use that app again. NurseJobs and '
            'NurseNow are force-updated independently of each other.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
          else ...[
            for (final app in const ['nursejobs', 'nursenow'])
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                child: _AppVersionsAppSection(
                  app: app,
                  versions: _versions.where((v) => v.app == app).toList(),
                  onEdit: _showEditDialog,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AppVersionsAppSection extends StatelessWidget {
  final String app;
  final List<AppMinVersion> versions;
  final void Function(AppMinVersion) onEdit;

  const _AppVersionsAppSection({required this.app, required this.versions, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _appDisplayName(app),
          style: const TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final version in versions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          version.platform[0].toUpperCase() + version.platform.substring(1),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.subtitle),
                        ),
                        const SizedBox(height: 4),
                        Text('Minimum version: ${version.minVersion}'),
                        if (version.storeUrl != null && version.storeUrl!.isNotEmpty)
                          Text('Store URL: ${version.storeUrl}',
                              style: const TextStyle(color: AppColors.textSecondary)),
                        if (version.updateMessage != null && version.updateMessage!.isNotEmpty)
                          Text('Message: ${version.updateMessage}',
                              style: const TextStyle(color: AppColors.textSecondary)),
                        if (version.updatedByName != null)
                          Text(
                            'Last updated by ${version.updatedByName}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
                          ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () => onEdit(version), child: const Text('Edit')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
