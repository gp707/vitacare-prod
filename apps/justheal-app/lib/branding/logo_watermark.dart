import 'package:flutter/material.dart';

/// Draws the JustHeal logo very faintly behind [child] — a smaller one near
/// the top and a large one in the lower half of the screen — used behind the login and
/// registration screens. It is purely decorative: it ignores touches and is
/// excluded from semantics.
class LogoWatermark extends StatelessWidget {
  final Widget child;

  const LogoWatermark({super.key, required this.child});

  /// Low enough that text and fields on top stay fully readable.
  static const opacity = 0.04;

  /// Vertical position (-1 = top edge, 1 = bottom edge) and width (fraction
  /// of the screen) of each mark. The lower one is the original watermark.
  static const _topY = -0.9;
  static const _topWidth = 0.8;
  static const _lowerY = 0.6;
  static const _lowerWidth = 0.8;

  Widget _mark(double y, double width) {
    return Align(
      alignment: Alignment(0, y),
      child: FractionallySizedBox(
        widthFactor: width,
        child: Opacity(
          opacity: opacity,
          child: Image.asset(
            'packages/vitacare_ui/assets/branding/justheal_splash_logo.webp',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _mark(_topY, _topWidth),
                  _mark(_lowerY, _lowerWidth)
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
