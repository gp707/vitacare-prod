import 'package:flutter/material.dart';

/// Draws the JustHeal emblem very faintly behind [child], filling the
/// available space — used behind the login and registration screens. It is
/// purely decorative: it ignores touches and is excluded from semantics.
class LogoWatermark extends StatelessWidget {
  final Widget child;

  const LogoWatermark({super.key, required this.child});

  /// Low enough that text and fields on top stay fully readable.
  static const opacity = 0.14;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              // Below the vertical centre, so it sits under the form's lower half
              // rather than behind the headings.
              child: Align(
                alignment: const Alignment(0, 0.6),
                child: FractionallySizedBox(
                  widthFactor: 0.8,
                  child: Opacity(
                    opacity: opacity,
                    child: Image.asset(
                      'packages/vitacare_ui/assets/branding/justheal_splash_logo.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
