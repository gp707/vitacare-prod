import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'package:nursenow_app/patient_hospital/core/text_scale/text_scale_provider.dart';

/// Quick-tap accessibility control — shown in every main screen's AppBar
/// alongside RateCardButton/WhatsAppHelpButton, same placement convention.
///
/// Deliberately reads/writes the HOST app's own textScaleProvider rather
/// than a second, caregiver-local copy: there is only one real MaterialApp/
/// Navigator for this whole merged binary (see CaregiverSessionWatcher's
/// own doc comment in app/app.dart, and CLAUDE.md's JustHeal merge notes)
/// — the MediaQuery override that actually renders the scaled text lives
/// once, in the host's own MaterialApp.builder (patient_hospital/app/
/// app.dart's PinchToZoomWrapper). A separate caregiver-side provider
/// instance would drift out of sync with what's actually on screen the
/// moment someone crossed between the two flows, since nothing would
/// listen to it.
class TextZoomButton extends ConsumerWidget {
  const TextZoomButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(textScaleProvider);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Text Size',
        child: ElevatedButton(
          onPressed: () => ref.read(textScaleProvider.notifier).cycleNext(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: Text(
            _shortLabel(scale),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.small),
          ),
        ),
      ),
    );
  }

  String _shortLabel(double scale) {
    var nearestIndex = 0;
    var smallestDiff = double.infinity;
    for (var i = 0; i < TextScaleLevels.steps.length; i++) {
      final diff = (TextScaleLevels.steps[i] - scale).abs();
      if (diff < smallestDiff) {
        smallestDiff = diff;
        nearestIndex = i;
      }
    }
    return 'A${'+' * nearestIndex}';
  }
}
