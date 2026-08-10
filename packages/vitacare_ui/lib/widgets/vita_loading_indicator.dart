import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Consistent loading spinner used across both apps.
class VitaLoadingIndicator extends StatelessWidget {
  final double size;

  const VitaLoadingIndicator({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
    );
  }
}
