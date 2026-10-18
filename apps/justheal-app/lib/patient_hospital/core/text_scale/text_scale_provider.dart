import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../storage/local_storage.dart';

/// Accessibility text/UI scale — two ways to change it, one shared value:
/// a quick-tap button (TextZoomButton) cycles through [steps], and a
/// two-finger pinch anywhere in the app (see PinchToZoomWrapper) adjusts
/// it continuously. Clamped to [min]/[max] so no screen's layout is ever
/// asked to render beyond what's actually been tested.
class TextScaleLevels {
  TextScaleLevels._();
  static const min = 1.0;
  static const max = 1.3;
  static const steps = [1.0, 1.15, 1.3];
}

class TextScaleNotifier extends StateNotifier<double> {
  final LocalStorage _localStorage;

  TextScaleNotifier(this._localStorage) : super(_localStorage.textScale);

  /// Jumps to the next fixed step strictly above the current value,
  /// wrapping back to the smallest step once past the top — this reads
  /// from wherever the scale currently sits (including a mid-step value
  /// left by a pinch gesture), not just the button's own last tap, so
  /// tapping again after a pinch always moves predictably forward.
  Future<void> cycleNext() async {
    final next = TextScaleLevels.steps.firstWhere(
      (step) => step > state + 0.01,
      orElse: () => TextScaleLevels.steps.first,
    );
    state = next;
    await _localStorage.setTextScale(next);
  }

  /// Continuous update from an in-progress pinch gesture — not persisted
  /// on every call (that would hammer SharedPreferences mid-gesture); see
  /// [persist].
  void setContinuous(double scale) {
    state = scale.clamp(TextScaleLevels.min, TextScaleLevels.max);
  }

  /// Persists wherever the scale currently sits — called once a pinch
  /// gesture ends (every finger lifted), not mid-gesture.
  Future<void> persist() => _localStorage.setTextScale(state);
}

final textScaleProvider = StateNotifierProvider<TextScaleNotifier, double>(
  (ref) => TextScaleNotifier(ref.watch(localStorageProvider)),
);
