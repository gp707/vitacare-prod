import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';

/// Lets an admin edit the 3 cumulative bullet lists (Companion Care /
/// Bedside Care / Critical Care) shown to caregivers (NurseJobs) via a
/// per-job "Scope of Work" popup — which tier a job's popup shows is
/// derived automatically from that job's care needs, never picked here.
/// Unlike RateCardScreen's fixed 3x3 grid, each tier here is a free-length
/// bullet list — bullets can be added or removed, not just edited in place.
class ScopeOfWorkScreen extends ConsumerStatefulWidget {
  const ScopeOfWorkScreen({super.key});

  @override
  ConsumerState<ScopeOfWorkScreen> createState() => _ScopeOfWorkScreenState();
}

class _ScopeOfWorkScreenState extends ConsumerState<ScopeOfWorkScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;
  String? _updatedByName;
  String? _updatedAt;

  List<TextEditingController> _companionControllers = [];
  List<TextEditingController> _bedsideControllers = [];
  List<TextEditingController> _criticalControllers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [..._companionControllers, ..._bedsideControllers, ..._criticalControllers]) {
      c.dispose();
    }
    super.dispose();
  }

  List<TextEditingController> _controllersFor(List<String> bullets) =>
      bullets.map((b) => TextEditingController(text: b)).toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final withUpdater = await ref.read(scopeOfWorkRepositoryProvider).get();
      if (!mounted) return;
      final scopeOfWork = withUpdater.scopeOfWork;
      setState(() {
        _companionControllers = _controllersFor(scopeOfWork.companionCare);
        _bedsideControllers = _controllersFor(scopeOfWork.bedsideCare);
        _criticalControllers = _controllersFor(scopeOfWork.criticalCare);
        _updatedByName = withUpdater.updatedByName;
        _updatedAt = withUpdater.updatedAt;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final scopeOfWork = ScopeOfWorkModel(
        companionCare: _companionControllers.map((c) => c.text.trim()).toList(),
        bedsideCare: _bedsideControllers.map((c) => c.text.trim()).toList(),
        criticalCare: _criticalControllers.map((c) => c.text.trim()).toList(),
      );
      await ref.read(scopeOfWorkRepositoryProvider).update(scopeOfWork);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scope of work saved')),
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
    return AppShell(
      current: AppShellSection.scopeOfWork,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Scope of Work',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Caregiving tasks shown to caregivers (NurseJobs) via a per-job popup. '
                'Which tier a job shows is derived automatically from that job\'s care needs — '
                'Bedside Care and Critical Care are cumulative ("everything in the tier(s) below, plus…").',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildForm(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) ...[
          Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        _buildTierSection(
          title: 'Companion Care',
          controllers: _companionControllers,
          onChanged: (updated) => setState(() => _companionControllers = updated),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildTierSection(
          title: 'Bedside Care',
          subtitle: 'Everything in Companion Care, plus:',
          controllers: _bedsideControllers,
          onChanged: (updated) => setState(() => _bedsideControllers = updated),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildTierSection(
          title: 'Critical Care',
          subtitle: 'Everything in Bedside Care, plus:',
          controllers: _criticalControllers,
          onChanged: (updated) => setState(() => _criticalControllers = updated),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_updatedByName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Last updated by $_updatedByName${_updatedAt != null ? ' on $_updatedAt' : ''}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildTierSection({
    required String title,
    String? subtitle,
    required List<TextEditingController> controllers,
    required void Function(List<TextEditingController>) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < controllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controllers[i],
                      decoration: const InputDecoration(labelText: 'Bullet'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    tooltip: 'Remove bullet',
                    onPressed: () {
                      final updated = [...controllers];
                      updated.removeAt(i).dispose();
                      onChanged(updated);
                    },
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () => onChanged([...controllers, TextEditingController()]),
            icon: const Icon(Icons.add),
            label: const Text('Add bullet'),
          ),
        ],
      ),
    );
  }
}
