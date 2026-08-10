import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/dashboard_repository.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardStats? _stats;
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
      final stats = await ref.read(dashboardRepositoryProvider).getStats();
      if (mounted) setState(() => _stats = stats);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToCaregivers({String? status}) {
    Navigator.of(context).pushNamed('/caregivers', arguments: status);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.dashboard,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Dashboard', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
              else if (_stats != null)
                Expanded(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        _StatCard(label: 'Total Caregivers', value: _stats!.totalCaregivers, onTap: () => _goToCaregivers()),
                        _StatCard(
                          label: 'Pending Call',
                          value: _stats!.pendingCall,
                          color: AppColors.statusPendingCall,
                          onTap: () => _goToCaregivers(status: 'pending_call'),
                        ),
                        _StatCard(
                          label: 'Call Verified',
                          value: _stats!.callVerified,
                          color: AppColors.statusCallVerified,
                          onTap: () => _goToCaregivers(status: 'call_verified'),
                        ),
                        _StatCard(
                          label: 'Pending Verification',
                          value: _stats!.pendingVerification,
                          color: AppColors.statusPendingVerification,
                          onTap: () => _goToCaregivers(status: 'pending_verification'),
                        ),
                        _StatCard(
                          label: 'In Process',
                          value: _stats!.inProcess,
                          color: AppColors.statusInProcess,
                          onTap: () => _goToCaregivers(status: 'in_process'),
                        ),
                        _StatCard(
                          label: 'Verified',
                          value: _stats!.available,
                          color: AppColors.statusAvailable,
                          onTap: () => _goToCaregivers(status: 'available'),
                        ),
                        _StatCard(
                          label: 'Rejected',
                          value: _stats!.rejected,
                          color: AppColors.statusRejected,
                          onTap: () => _goToCaregivers(status: 'rejected'),
                        ),
                        _StatCard(label: 'New (24h)', value: _stats!.newRegistrations24h),
                        _StatCard(label: 'New (7d)', value: _stats!.newRegistrations7d),
                        _StatCard(
                          label: 'Pending Edits',
                          value: _stats!.pendingEditsCount,
                          color: AppColors.warning,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color? color;
  final VoidCallback? onTap;

  const _StatCard({required this.label, required this.value, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color ?? AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
