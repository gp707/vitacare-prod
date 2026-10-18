import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/text_scale/text_scale_provider.dart';

/// Lets anyone pinch with two fingers anywhere in the app to scale up
/// text/UI, applied via a MediaQuery textScaler override above the whole
/// app (see app.dart's MaterialApp.builder) — the same scale TextZoomButton
/// cycles through, so both controls drive one shared, persisted value.
///
/// Deliberately built on a raw [Listener] (tracking pointer-down/move/up by
/// hand) rather than GestureDetector's onScale* callbacks. GestureDetector
/// would register a ScaleGestureRecognizer that competes in the gesture
/// arena with every descendant's own recognizer (a ListView's vertical
/// drag, a button's tap) — since this wrapper sits above the entire app,
/// that risks hijacking ordinary single-finger scrolling/tapping
/// throughout every screen. Listener never enters the arena; it only
/// observes pointer events as a side channel, so descendants keep
/// receiving and winning their own gestures completely normally. Only
/// once a second pointer actually lands do we start tracking a pinch at
/// all — a single finger never touches the scale.
class PinchToZoomWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const PinchToZoomWrapper({super.key, required this.child});

  @override
  ConsumerState<PinchToZoomWrapper> createState() => _PinchToZoomWrapperState();
}

class _PinchToZoomWrapperState extends ConsumerState<PinchToZoomWrapper> {
  final Map<int, Offset> _pointers = {};
  double? _initialDistance;
  double _baseScale = 1.0;

  double _distanceBetween(Offset a, Offset b) => (a - b).distance;

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      final points = _pointers.values.toList();
      _initialDistance = _distanceBetween(points[0], points[1]);
      _baseScale = ref.read(textScaleProvider);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    final initialDistance = _initialDistance;
    if (_pointers.length == 2 && initialDistance != null && initialDistance > 0) {
      final points = _pointers.values.toList();
      final currentDistance = _distanceBetween(points[0], points[1]);
      ref.read(textScaleProvider.notifier).setContinuous(_baseScale * (currentDistance / initialDistance));
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _initialDistance = null;
    }
    if (_pointers.isEmpty) {
      ref.read(textScaleProvider.notifier).persist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = ref.watch(textScaleProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: widget.child,
      ),
    );
  }
}
