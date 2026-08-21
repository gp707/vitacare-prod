import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/admin_users_repository.dart';

class AdminManagementScreen extends ConsumerStatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  ConsumerState<AdminManagementScreen> createState() =>
      _AdminManagementScreenState();
}

class _AdminManagementScreenState extends ConsumerState<AdminManagementScreen> {
  List<AdminUser> _admins = [];
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
      final admins = await ref.read(adminUsersRepositoryProvider).list();
      if (mounted) setState(() => _admins = admins);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateDialog() async {
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    String? dialogError;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Admin'),
          content: SizedBox(
            width: context.dialogWidth(400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                      labelText: 'Phone', prefixText: '+91 '),
                ),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
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
                  await ref.read(adminUsersRepositoryProvider).create(
                        email: emailController.text.trim(),
                        phone: '+91${phoneController.text.trim()}',
                        fullName: nameController.text.trim(),
                        password: passwordController.text,
                      );
                  if (context.mounted) Navigator.of(context).pop(true);
                } on ApiException catch (e) {
                  setDialogState(() => dialogError = e.message);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (created == true) await _load();
  }

  Future<void> _confirmDeactivate(AdminUser admin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate admin?'),
        content: Text('Are you sure you want to deactivate ${admin.fullName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(adminUsersRepositoryProvider).deactivate(admin.userId);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _activate(AdminUser admin) async {
    try {
      await ref.read(adminUsersRepositoryProvider).activate(admin.userId);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _confirmMakeSuperAdmin(AdminUser admin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make Super Admin?'),
        content: Text(
            '${admin.fullName} will get full access, including managing other admins.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Make Super Admin'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(adminUsersRepositoryProvider)
          .updateRole(admin.userId, 'super_admin');
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.adminManagement,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Expanded + ellipsis so the button is never pushed off
                  // (and never forces a RenderFlex overflow) on a narrow
                  // viewport.
                  const Expanded(
                    child: Text(
                      'Admin Management',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton.icon(
                    onPressed: _showCreateDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Admin'),
                  ),
                ],
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
    if (_admins.isEmpty) return const Center(child: Text('No admins found.'));
    return ListView.separated(
      itemCount: _admins.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final admin = _admins[index];
        return ListTile(
          title: Text(admin.fullName),
          subtitle: Text('${admin.email} · ${admin.phone} · ${admin.role}'),
          trailing: admin.role == 'super_admin'
              ? const Chip(label: Text('Super Admin'))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(admin.isActive ? 'Active' : 'Deactivated'),
                      backgroundColor: admin.isActive
                          ? AppColors.primaryLight
                          : AppColors.border,
                    ),
                    if (admin.isActive) ...[
                      IconButton(
                        onPressed: () => _confirmMakeSuperAdmin(admin),
                        icon: const Icon(Icons.upgrade),
                        tooltip: 'Make Super Admin',
                      ),
                      IconButton(
                        onPressed: () => _confirmDeactivate(admin),
                        icon: const Icon(Icons.block, color: AppColors.error),
                        tooltip: 'Deactivate',
                      ),
                    ] else
                      IconButton(
                        onPressed: () => _activate(admin),
                        icon: const Icon(Icons.check_circle_outline,
                            color: AppColors.success),
                        tooltip: 'Activate',
                      ),
                  ],
                ),
        );
      },
    );
  }
}
