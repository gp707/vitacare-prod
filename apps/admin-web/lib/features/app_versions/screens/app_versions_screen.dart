import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/app_versions_repository.dart';

/// Lets an admin force-upgrade the caregiver mobile app: raising a
/// platform's min_version above what a caregiver has installed blocks them
/// with an "Update Required" screen on their next launch (see
/// AppVersionRepository.checkForUpdate in the caregiver app).
class AppVersionsScreen extends ConsumerStatefulWidget {
  const AppVersionsScreen({super.key});

  @override
  ConsumerState<AppVersionsScreen> createState() => _AppVersionsScreenState();
}

class _AppVersionsScreenState extends ConsumerState<AppVersionsScreen> {
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
    final minVersionController =
        TextEditingController(text: version.minVersion);
    final storeUrlController =
        TextEditingController(text: version.storeUrl ?? '');
    final updateMessageController =
        TextEditingController(text: version.updateMessage ?? '');
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${version.platform} minimum version'),
          content: SizedBox(
            width: context.dialogWidth(420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: minVersionController,
                  decoration: const InputDecoration(
                      labelText: 'Minimum version (e.g. 1.2.0)'),
                ),
                TextField(
                  controller: storeUrlController,
                  decoration: const InputDecoration(labelText: 'Store URL'),
                ),
                TextField(
                  controller: updateMessageController,
                  decoration: const InputDecoration(
                      labelText: 'Update message (shown to caregiver)'),
                  maxLines: 2,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(dialogError!,
                      style: const TextStyle(color: AppColors.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ref.read(appVersionsRepositoryProvider).update(
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
    return AppShell(
      current: AppShellSection.appVersions,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('App Versions',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Raise a platform\'s minimum version above what a caregiver has installed to '
                'force them to update before they can use the app again.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!,
                    style: const TextStyle(color: AppColors.error))
              else
                Expanded(child: _buildList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      itemCount: _versions.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final version = _versions[index];
        return Container(
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
                      version.platform[0].toUpperCase() +
                          version.platform.substring(1),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text('Minimum version: ${version.minVersion}'),
                    if (version.storeUrl != null &&
                        version.storeUrl!.isNotEmpty)
                      Text('Store URL: ${version.storeUrl}',
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                    if (version.updateMessage != null &&
                        version.updateMessage!.isNotEmpty)
                      Text('Message: ${version.updateMessage}',
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                    if (version.updatedByName != null)
                      Text(
                        'Last updated by ${version.updatedByName}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              TextButton(
                  onPressed: () => _showEditDialog(version),
                  child: const Text('Edit')),
            ],
          ),
        );
      },
    );
  }
}
