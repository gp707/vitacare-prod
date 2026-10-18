import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../core/text_scale/text_scale_provider.dart';

/// Quick-tap accessibility control — shown in every main screen's AppBar
/// alongside RateCardButton/WhatsAppHelpButton, same placement convention.
/// Cycles the app-wide text/UI scale through TextScaleLevels.steps on each
/// tap (wrapping back to Normal after the top step); a two-finger pinch
/// anywhere in the app (see PinchToZoomWrapper) adjusts the same value
/// continuously — both drive one shared, persisted scale. Shows only the
/// 'A'/'A+'/'A++' label (no icon) — Icons.text_increase's own glyph
/// already looks like a stylized "A+", so pairing it with this label read
/// as a confusing "A+A"; the plain label alone is also the more
/// universally recognized affordance for this (same convention as native
/// iOS/Android "Larger Text" toggles). A tooltip carries the accessible
/// label for anyone using a screen reader.
class TextZoomButton extends ConsumerWidget {
  const TextZoomButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(textScaleProvider);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: 'Text Size',
        child: ElevatedButton(
          onPressed: () => ref.read(textScaleProvider.notifier).cycleNext(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: Text(
            _shortLabel(scale),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.caption),
          ),
        ),
      ),
    );
  }

  // 'A', 'A+' or 'A++' — a quick glance at the button itself already shows
  // roughly which of the 3 steps the current scale is nearest to (a pinch
  // gesture can leave it anywhere in between two fixed steps), not just
  // the whole screen's text having visibly grown.
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
