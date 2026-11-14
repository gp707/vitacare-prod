import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/read_only_admin.dart';

/// Hides [child] from a read-only admin — wrap any button that does something
/// they can't (the API refuses it anyway; this just keeps it off the screen).
class HideForReadOnly extends ConsumerWidget {
  final Widget child;

  const HideForReadOnly({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(isReadOnlyAdminProvider) ? const SizedBox.shrink() : child;
}
